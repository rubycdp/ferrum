# frozen_string_literal: true

require "net/http"
require "json"
require "addressable"
require "tmpdir"
require "forwardable"
require "ferrum/browser/options/base"
require "ferrum/browser/options/chrome"
require "ferrum/browser/process/killer"
require "ferrum/browser/process/output"
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
      WS_URL = %r{DevTools listening on (ws://.*[a-zA-Z0-9-]{36})}

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

      attr_reader :host, :port, :ws_url, :pid, :command, :xvfb

      # What the browser process wrote to stdout and stderr, empty for a
      # browser Ferrum didn't launch.
      #
      # @return [Output]
      attr_reader :output

      def initialize(options)
        @pid = @xvfb = @user_data_dir = nil
        @requested_host = options.host
        @log = options.log
        @output = Output.new(@log)

        if options.ws_url || options.url
          self.ws_url = options.ws_url || fetch_ws_url(options.url)
          return
        end

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
          @xvfb = Xvfb.start(@command.options) if @command.xvfb?
          @output = Output.new(@log)
          @output.pipe { |io| spawn_browser(io) }
          parse_ws_url
          @output.follow
        ensure
          @output.close unless ws_url
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
          "@ws_url=#{@ws_url.inspect}>"
      end

      private

      def spawn_browser(io)
        process_options = { in: File::NULL, out: io, err: io }
        process_options[:pgroup] = true unless Utils::Platform.windows?
        env = Hash(@xvfb&.to_env).merge(@env)

        @pid = ::Process.spawn(env, *@command.to_a, process_options)
        ObjectSpace.define_finalizer(self, Killer.finalizer([@pid, @xvfb&.pid], @user_data_dir))
      end

      def sync_stop
        if @pid
          Killer.kill(@pid)
          Killer.kill(@xvfb.pid) if @xvfb&.pid
          @pid = nil
        end

        @output.close
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
        output = @output
        @pid = @user_data_dir = nil

        Utils::Thread.spawn do
          Killer.kill(pid) if pid
          Killer.kill(xvfb_pid) if xvfb_pid
          output.close
          Killer.remove_directory(user_data_dir) if user_data_dir
          ObjectSpace.undefine_finalizer(self)
        end
      end

      def remove_user_data_dir
        Killer.remove_directory(@user_data_dir)
        @user_data_dir = nil
      end

      def parse_ws_url
        match = @output.wait_for(WS_URL, @process_timeout)
        raise ProcessTimeoutError.new(@process_timeout, @output.to_s) unless match

        self.ws_url = rewrite_host(match[1].strip)
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

      def fetch_ws_url(url)
        response = ::Net::HTTP.get_response(URI(json_version_url(url).to_s))
        status = "#{response.code} #{response.message}" unless response.is_a?(::Net::HTTPSuccess)
        ws_url = begin
          JSON.parse(response.body.to_s)["webSocketDebuggerUrl"]
        rescue JSON::ParserError
          nil
        end

        reachable_ws_url(ws_url, url) || raise(NoWebSocketUrlError.new(url, status))
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
