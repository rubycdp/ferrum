# frozen_string_literal: true

require "cliver"
require "net/http"
require "json"
require "addressable"
require "tmpdir"

module Ferrum
  class Browser
    class Process
      KILL_TIMEOUT = 2
      WAIT_KILLED = 0.05
      PROCESS_TIMEOUT = ENV.fetch("FERRUM_PROCESS_TIMEOUT", 2).to_i
      BROWSER_PATH = ENV["BROWSER_PATH"]
      BROWSER_HOST = "127.0.0.1"
      BROWSER_PORT = "0"
      DEFAULT_OPTIONS = {
        "headless" => nil,
        "disable-gpu" => nil,
        "hide-scrollbars" => nil,
        "mute-audio" => nil,
        "enable-automation" => nil,
        "disable-web-security" => nil,
        "disable-session-crashed-bubble" => nil,
        "disable-breakpad" => nil,
        "disable-sync" => nil,
        "no-first-run" => nil,
        "use-mock-keychain" => nil,
        "keep-alive-for-test" => nil,
        "disable-popup-blocking" => nil,
        "disable-extensions" => nil,
        "disable-hang-monitor" => nil,
        "disable-features" => "site-per-process,TranslateUI",
        "disable-translate" => nil,
        "disable-background-networking" => nil,
        "enable-features" => "NetworkService,NetworkServiceInProcess",
        "disable-background-timer-throttling" => nil,
        "disable-backgrounding-occluded-windows" => nil,
        "disable-client-side-phishing-detection" => nil,
        "disable-default-apps" => nil,
        "disable-dev-shm-usage" => nil,
        "disable-ipc-flooding-protection" => nil,
        "disable-prompt-on-repost" => nil,
        "disable-renderer-backgrounding" => nil,
        "force-color-profile" => "srgb",
        "metrics-recording-only" => nil,
        "safebrowsing-disable-auto-update" => nil,
        "password-store" => "basic",
        # Note: --no-sandbox is not needed if you properly setup a user in the container.
        # https://github.com/ebidel/lighthouse-ci/blob/master/builder/Dockerfile#L35-L40
        # "no-sandbox" => nil,
      }.freeze

      NOT_FOUND = "Could not find an executable for chrome. Try to make it " \
                  "available on the PATH or set environment varible for " \
                  "example BROWSER_PATH=\"/Applications/Chromium.app/Contents/MacOS/Chromium\""


      attr_reader :host, :port, :ws_url, :pid, :path, :options, :cmd, :default_user_agent

      def self.start(*args)
        new(*args).tap(&:start)
      end

      def self.process_killer(pid)
        proc do
          begin
            if Ferrum.windows?
              ::Process.kill("KILL", pid)
            else
              ::Process.kill("USR1", pid)
              start = Ferrum.monotonic_time
              while ::Process.wait(pid, ::Process::WNOHANG).nil?
                sleep(WAIT_KILLED)
                next unless Ferrum.timeout?(start, KILL_TIMEOUT)
                ::Process.kill("KILL", pid)
                ::Process.wait(pid)
                break
              end
            end
          rescue Errno::ESRCH, Errno::ECHILD
          end
        end
      end

      def self.directory_remover(path)
        proc do
          begin
            FileUtils.remove_entry(path)
          rescue Errno::ENOENT
          end
        end
      end

      def self.detect_browser_path
        if RUBY_PLATFORM.include?("darwin")
          [
            "/Applications/Chromium.app/Contents/MacOS/Chromium",
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
          ].find { |path| File.exist?(path) }
        else
          %w[chromium google-chrome-unstable google-chrome-beta google-chrome chrome chromium-browser google-chrome-stable].reduce(nil) do |path, exe|
            path = Cliver.detect(exe)
            break path if path
          end
        end
      end

      def initialize(options)
        @options = {}

        @path = options[:browser_path] || BROWSER_PATH || self.class.detect_browser_path

        if options[:url]
          url = URI.join(options[:url].to_s, "/json/version")
          response = JSON.parse(::Net::HTTP.get(url))
          set_ws_url(response["webSocketDebuggerUrl"])
          set_default_user_agent
          return
        end

        # Doesn't work on MacOS, so we need to set it by CDP as well
        @options.merge!("window-size" => options[:window_size].join(","))

        port = options.fetch(:port, BROWSER_PORT)
        @options.merge!("remote-debugging-port" => port)

        host = options.fetch(:host, BROWSER_HOST)
        @options.merge!("remote-debugging-address" => host)

        @temp_user_data_dir = Dir.mktmpdir
        ObjectSpace.define_finalizer(self, self.class.directory_remover(@temp_user_data_dir))
        @options.merge!("user-data-dir" => @temp_user_data_dir)

        @options = DEFAULT_OPTIONS.merge(@options)

        unless options.fetch(:headless, true)
          @options.delete("headless")
          @options.delete("disable-gpu")
        end

        @process_timeout = options.fetch(:process_timeout, PROCESS_TIMEOUT)

        @options.merge!(options.fetch(:browser_options, {}))

        @logger = options[:logger]
      end

      def start
        # Don't do anything as browser is already running as external process.
        return if ws_url

        begin
          read_io, write_io = IO.pipe
          process_options = { in: File::NULL }
          process_options[:pgroup] = true unless Ferrum.windows?
          process_options[:out] = process_options[:err] = write_io

          raise Cliver::Dependency::NotFound.new(NOT_FOUND) unless @path

          @cmd = [@path] + @options.map { |k, v| v.nil? ? "--#{k}" : "--#{k}=#{v}" }
          @pid = ::Process.spawn(*@cmd, process_options)
          ObjectSpace.define_finalizer(self, self.class.process_killer(@pid))

          parse_ws_url(read_io, @process_timeout)
          set_default_user_agent
        ensure
          close_io(read_io, write_io)
        end
      end

      def stop
        kill if @pid
        remove_temp_user_data_dir if @temp_user_data_dir
        ObjectSpace.undefine_finalizer(self)
      end

      def restart
        stop
        start
      end

      private

      def kill
        self.class.process_killer(@pid).call
        @pid = nil
      end

      def remove_temp_user_data_dir
        self.class.directory_remover(@temp_user_data_dir).call
        @temp_user_data_dir = nil
      end

      def parse_ws_url(read_io, timeout)
        output = ""
        start = Ferrum.monotonic_time
        max_time = start + timeout
        regexp = /DevTools listening on (ws:\/\/.*)/
        while (now = Ferrum.monotonic_time) < max_time
          begin
            output += read_io.read_nonblock(512)
          rescue IO::WaitReadable
            IO.select([read_io], nil, nil, max_time - now)
          else
            if output.match(regexp)
              set_ws_url(output.match(regexp)[1].strip)
              break
            end
          end
        end

        unless ws_url
          @logger.puts output if @logger
          raise "Chrome process did not produce websocket url within #{timeout} seconds"
        end
      end

      def set_ws_url(url)
        @ws_url = Addressable::URI.parse(url)
        @host = @ws_url.host
        @port = @ws_url.port
      end

      def set_default_user_agent
        return unless ws_url.is_a? Addressable::URI

        version_url = URI.parse(ws_url.merge(scheme: "http", path: "/json/version"))
        response = JSON.parse(::Net::HTTP.get(version_url))
        @default_user_agent = response["User-Agent"]
      end

      def close_io(*ios)
        ios.each do |io|
          begin
            io.close unless io.closed?
          rescue IOError
            raise unless RUBY_ENGINE == "jruby"
          end
        end
      end
    end
  end
end
