# frozen_string_literal: true

require "uri"
require "net/http"
require "rack/handler/puma"
require "support/application"

module Ferrum
  class Server
    KILL_TIMEOUT = 60

    class Middleware
      class Counter
        attr_reader :value

        def initialize
          @value = 0
          @mutex = Mutex.new
        end

        def increment
          @mutex.synchronize { @value += 1 }
        end

        def decrement
          @mutex.synchronize { @value -= 1 }
        end
      end

      def initialize(app)
        @app = app
        @counter = Counter.new
      end

      def pending_requests?
        @counter.value.positive?
      end

      def call(env)
        if env["PATH_INFO"] == "/__identify__"
          [200, {}, [@app.object_id.to_s]]
        else
          @counter.increment
          begin
            @app.call(env)
          ensure
            @counter.decrement
          end
        end
      end
    end

    class << self
      attr_accessor :server

      def boot(**options)
        new(**options).tap(&:boot!)
      end
    end

    attr_reader :app, :host, :port

    def initialize(app: nil, host: "127.0.0.1", port: nil)
      @host = host
      @port = port || find_available_port(host)
      @app = app || Application.new
      @server_thread = nil
    end

    def base_url(path = nil)
      "http://#{host}:#{port}" + path.to_s
    end

    def wait_for_pending_requests
      start = Utils::ElapsedTime.monotonic_time
      while pending_requests?
        raise "Requests did not finish in #{KILL_TIMEOUT} seconds" if Utils::ElapsedTime.timeout?(start, KILL_TIMEOUT)

        sleep 0.01
      end
    end

    def boot!
      return if responsive?

      start = Utils::ElapsedTime.monotonic_time
      @server_thread = Thread.new { run }

      until responsive?
        raise "Rack application timed out during boot" if Utils::ElapsedTime.timeout?(start, KILL_TIMEOUT)

        @server_thread.join(0.1)
      end

      self.class.server = self
    end

    private

    def middleware
      @middleware ||= Middleware.new(app)
    end

    def run
      options = { Host: host, Port: port, Threads: "0:4", workers: 0, daemon: false }
      config = Rack::Handler::Puma.config(middleware, options)
      events = config.options[:Silent] ? ::Puma::Events.strings : ::Puma::Events.stdio

      events.log "Starting Puma"
      events.log "* Version #{Puma::Const::PUMA_VERSION} , codename: #{Puma::Const::CODE_NAME}"
      events.log "* Min threads: #{config.options[:min_threads]}, max threads: #{config.options[:max_threads]}"

      Puma::Server.new(config.app, events, config.options).tap do |s|
        s.binder.parse(config.options[:binds], s.events)
        s.min_threads = config.options[:min_threads]
        s.max_threads = config.options[:max_threads]
      end.run.join
    end

    def responsive?
      return false if @server_thread&.join(0)

      res = Net::HTTP.start(host, port, read_timeout: 2, max_retries: 0) { |h| h.get("/__identify__") }
      return res.body == app.object_id.to_s if res.is_a?(Net::HTTPSuccess) || res.is_a?(Net::HTTPRedirection)
    rescue SystemCallError, Net::ReadTimeout
      false
    end

    def pending_requests?
      middleware.pending_requests?
    end

    def find_available_port(host)
      server = TCPServer.new(host, 0)
      server.addr[1]
    ensure
      server.close
    end
  end
end
