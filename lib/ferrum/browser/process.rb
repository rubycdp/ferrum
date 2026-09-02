# frozen_string_literal: true

require "net/http"
require "json"
require "addressable"
require "tmpdir"
require "forwardable"
require "ferrum/browser/options/base"
require "ferrum/browser/options/chrome"
require "ferrum/browser/options/firefox"
require "ferrum/browser/process/killer"
require "ferrum/browser/command"
require "ferrum/utils/elapsed_time"
require "ferrum/utils/platform"
require "ferrum/utils/thread"

module Ferrum
  class Browser
    #
    # Spawns and manages the lifecycle of the browser OS process: builds the
    # launch {Command}, starts it (optionally under {Xvfb} for headful mode),
    # waits for the CDP WebSocket endpoint to become available, and handles
    # stopping/restarting the process and cleaning up its user data directory.
    #
    class Process
      extend Forwardable

      HTTP_SCHEMES = { "ws" => "http", "wss" => "https" }.freeze
      WS_SCHEMES = { "http" => "ws", "https" => "wss" }.freeze
      LOCAL_HOSTS = %w[0.0.0.0 :: 127.0.0.1 ::1 localhost].freeze

      delegate path: :command

      #
      # Builds and starts a new browser process.
      #
      # @param [Array] args
      #   Arguments forwarded to {#initialize}.
      #
      # @return [Process]
      #
      def self.start(*args)
        new(*args).tap(&:start)
      end

      attr_reader :host, :port, :ws_url, :pid, :command,
                  :default_user_agent, :browser_version, :protocol_version,
                  :v8_version, :webkit_version, :xvfb

      def initialize(options)
        @pid = @xvfb = @user_data_dir = nil
        @requested_host = options.host

        if options.ws_url || options.url
          # `:ws_url` option is higher priority than `:url`, parse versions
          # and use it as a ws_url, otherwise use what has been parsed.
          endpoint = options.ws_url || options.url
          response = parse_json_version(endpoint)
          ws_url = options.ws_url || reachable_ws_url(response&.[]("webSocketDebuggerUrl"), endpoint)
          raise NoWebSocketUrlError, endpoint unless ws_url

          self.ws_url = ws_url
          return
        end

        @logger = options.logger
        @process_timeout = options.process_timeout
        @env = Hash(options.env)

        @user_data_dir = Dir.mktmpdir("ferrum_user_data_dir_")
        @command = Command.build(options, @user_data_dir)
      end

      #
      # Spawns the browser process and waits for it to become reachable over CDP.
      #
      # @return [void]
      #
      def start
        # Don't do anything as browser is already running as external process.
        return if ws_url

        begin
          read_io, write_io = IO.pipe
          process_options = { in: File::NULL }
          process_options[:pgroup] = true unless Utils::Platform.windows?
          process_options[:out] = process_options[:err] = write_io

          @xvfb = Xvfb.start(@command.options) if @command.xvfb?

          env = Hash(@xvfb&.to_env).merge(@env)
          @pid = ::Process.spawn(env, *@command.to_a, process_options)
          ObjectSpace.define_finalizer(self, Killer.finalizer([@pid, @xvfb&.pid], @user_data_dir))

          parse_ws_url(read_io, @process_timeout)
          parse_json_version(ws_url)
        ensure
          close_io(read_io, write_io)
        end
      end

      #
      # Kills the browser process (and Xvfb, if running) and removes the user
      # data directory.
      #
      # @param [Boolean] wait
      #   Whether to block until the process is confirmed dead and its user
      #   data directory removed (the default), or return immediately and
      #   run that cleanup on a background thread instead. Killing a
      #   stubborn process group can block for up to {Killer::KILL_TIMEOUT}
      #   seconds, plus retries removing its directory, which matters when quitting
      #   many browsers in a hot path. `wait: false` is not used by
      #   {#restart}, which always waits so the old process is fully gone
      #   before the new one starts.
      #
      # @return [Thread, nil]
      #   The background cleanup thread when `wait: false`; the caller can
      #   `#join` it if they need cleanup to have finished, e.g. before
      #   process exit or before reusing a fixed port. `nil` when `wait:
      #   true`.
      #
      def stop(wait: true)
        return sync_stop if wait

        async_stop
      end

      #
      # Stops and starts the browser process again.
      #
      # @return [void]
      #
      def restart
        stop
        start
      end

      #
      # Custom inspection that omits noisy internal command details.
      #
      # @return [String]
      #
      def inspect
        "#<#{self.class} " \
          "@user_data_dir=#{@user_data_dir.inspect} " \
          "@command=#<#{@command.class}:#{@command.object_id}> " \
          "@default_user_agent=#{@default_user_agent.inspect} " \
          "@ws_url=#{@ws_url.inspect} " \
          "@v8_version=#{@v8_version.inspect} " \
          "@browser_version=#{@browser_version.inspect} " \
          "@webkit_version=#{@webkit_version.inspect}>"
      end

      private

      def sync_stop
        if @pid
          Killer.kill(@pid)
          Killer.kill(@xvfb.pid) if @xvfb&.pid
          @pid = nil
        end

        remove_user_data_dir if @user_data_dir
        ObjectSpace.undefine_finalizer(self)
        nil
      end

      #
      # Snapshots what needs killing/removing, clears instance state so the
      # object looks stopped right away, and does the actual work on a
      # background thread. The finalizer is left in place as a backup until
      # that thread finishes, in case the process exits before it does.
      #
      def async_stop
        pid = @pid
        xvfb_pid = @xvfb&.pid
        user_data_dir = @user_data_dir
        @pid = @user_data_dir = nil

        Utils::Thread.spawn do
          Killer.kill(pid) if pid
          Killer.kill(xvfb_pid) if xvfb_pid
          Killer.remove_directory(user_data_dir) if user_data_dir
          ObjectSpace.undefine_finalizer(self)
        end
      end

      def remove_user_data_dir
        Killer.remove_directory(@user_data_dir)
        @user_data_dir = nil
      end

      def parse_ws_url(read_io, timeout)
        output = ""
        start = Utils::ElapsedTime.monotonic_time
        max_time = start + timeout
        regexp = %r{DevTools listening on (ws://.*[a-zA-Z0-9-]{36})}
        while (now = Utils::ElapsedTime.monotonic_time) < max_time
          begin
            output += read_io.read_nonblock(512)
          rescue IO::WaitReadable
            read_io.wait_readable(max_time - now)
          else
            if output.match(regexp)
              self.ws_url = rewrite_host(output.match(regexp)[1].strip)
              break
            end
          end
        end

        return if ws_url

        @logger&.puts(output)
        raise ProcessTimeoutError.new(timeout, output)
      end

      def ws_url=(url)
        @ws_url = Addressable::URI.parse(url)
        @host = @ws_url.host
        @port = @ws_url.port
      end

      def rewrite_host(url)
        uri = Addressable::URI.parse(url)
        uri.host = @requested_host
        uri.to_s
      end

      def close_io(*ios)
        ios.each do |io|
          io.close if io && !io.closed?
        rescue IOError
          raise unless RUBY_ENGINE == "jruby"
        end
      end

      def parse_json_version(url)
        response = JSON.parse(::Net::HTTP.get(URI(json_version_url(url).to_s)))

        @v8_version = response["V8-Version"]
        @browser_version = response["Browser"]
        @webkit_version = response["WebKit-Version"]
        @default_user_agent = response["User-Agent"]
        @protocol_version = response["Protocol-Version"]

        response
      rescue JSON::ParserError
        # nop
      end

      def json_version_url(url)
        url = Addressable::URI.parse(url).dup
        url.scheme = HTTP_SCHEMES.fetch(url.scheme, url.scheme)
        url.path = "/json/version"
        url
      end

      def reachable_ws_url(ws_url, endpoint)
        return unless ws_url

        ws_url = Addressable::URI.parse(ws_url)
        return ws_url.to_s unless LOCAL_HOSTS.include?(ws_url.host)

        url = Addressable::URI.parse(endpoint).dup
        url.scheme = WS_SCHEMES.fetch(url.scheme, url.scheme)
        url.path = ws_url.path
        url.to_s
      end
    end
  end
end
