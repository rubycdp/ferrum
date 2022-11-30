# frozen_string_literal: true

require "net/http"
require "json"
require "addressable"
require "tmpdir"
require "forwardable"
require "fcntl"
require "ferrum/browser/options/base"
require "ferrum/browser/options/chrome"
require "ferrum/browser/options/firefox"
require "ferrum/browser/command"

module Ferrum
  class Browser
    class Process
      KILL_TIMEOUT = 2
      WAIT_KILLED = 0.05

      attr_reader :host, :port, :ws_url, :pid, :command,
                  :default_user_agent, :browser_version, :protocol_version,
                  :v8_version, :webkit_version, :xvfb

      extend Forwardable
      delegate path: :command

      def self.start(*args)
        new(*args).tap(&:start)
      end

      def self.process_killer(pid, logger)
        proc do
          if Utils::Platform.windows?
            # Process.kill is unreliable on Windows
            ::Process.kill("KILL", pid) unless system("taskkill /f /t /pid #{pid} >NUL 2>NUL")
          else
            ::Process.kill("USR1", pid)
            logger&.puts("\nAttemping to kill #{pid}")
            start = Utils::ElapsedTime.monotonic_time
            while ::Process.wait(pid, ::Process::WNOHANG).nil?
              logger&.puts("Waiting for #{pid} to end")
              sleep(WAIT_KILLED)
              next unless Utils::ElapsedTime.timeout?(start, KILL_TIMEOUT)

              logger&.puts("Forcefully killing #{pid}")
              ::Process.kill("KILL", pid)
              ::Process.wait(pid)
              break
            end
          end
        rescue Errno::ESRCH, Errno::ECHILD
          # nop
        end
      end

      def self.directory_remover(path)
        proc {
          begin
            FileUtils.remove_entry(path)
          rescue StandardError
            Errno::ENOENT
          end
        }
      end

      def initialize(options)
        @pid = @xvfb = @user_data_dir = nil

        if options.url
          url = URI.join(options.url, "/json/version")
          response = JSON.parse(::Net::HTTP.get(url))
          self.ws_url = response["webSocketDebuggerUrl"]
          parse_browser_versions
          return
        end

        @logger = options.logger
        @process_timeout = options.process_timeout
        @env = Hash(options.env)

        tmpdir = Dir.mktmpdir("ferrum_user_data_dir_")
        ObjectSpace.define_finalizer(self, self.class.directory_remover(tmpdir))
        @user_data_dir = tmpdir
        @command = Command.build(options, tmpdir)
      end

      def start
        # Don't do anything as browser is already running as external process.
        return if ws_url

        if ENV["FERRUM_CHROME_LOG"]
          File.open(ENV["FERRUM_CHROME_LOG"], "w") do |output_log|
            launch_chrome(stdout_and_stderr: output_log)
            File.open(output_log.path, Fcntl::O_NONBLOCK|Fcntl::O_RDONLY) do |read_from_log|
              parse_ws_url(read_from_log, @process_timeout, @pid)
            end
          end
        else
          IO.pipe do |read_io, write_io|
            begin
              launch_chrome(stdout_and_stderr: write_io)
              read_io.fcntl(Fcntl::F_SETFL, read_io.fcntl(Fcntl::F_GETFL)|Fcntl::O_RDONLY)
              parse_ws_url(read_io, @process_timeout, @pid)
            ensure
              close_io(read_io, write_io)
            end
          end
        end

        parse_browser_versions
      end

      def launch_chrome(stdout_and_stderr:)
        process_options = { in: File::NULL }
        process_options[:pgroup] = true unless Utils::Platform.windows?
        process_options[:out] = process_options[:err] = stdout_and_stderr

        if @command.xvfb?
          @xvfb = Xvfb.start(@command.options)
          ObjectSpace.define_finalizer(self, self.class.process_killer(@xvfb.pid, @logger))
        end

        env = Hash(@xvfb&.to_env).merge(@env)
        @logger&.puts("\nAttemping to spawn chrome with:")
        @logger&.puts("  env: #{env}")
        @logger&.puts("  command: #{@command.to_a.join(' ')}")
        @logger&.puts("  process options: #{process_options}")
        @logger&.puts("")
        @pid = ::Process.spawn(env, *@command.to_a, process_options)
        @logger&.puts("spawned chrome (#{@pid}):\n" +`ps #{pid}`)
        ObjectSpace.define_finalizer(self, self.class.process_killer(@pid, @logger))
      end

      def stop
        if @pid
          kill(@pid)
          kill(@xvfb.pid) if @xvfb&.pid
          @pid = nil
        end

        remove_user_data_dir if @user_data_dir
        ObjectSpace.undefine_finalizer(self)
      end

      def restart
        stop
        start
      end

      private

      def kill(pid)
        self.class.process_killer(pid, @logger).call
      end

      def remove_user_data_dir
        self.class.directory_remover(@user_data_dir).call
        @user_data_dir = nil
      end

      def parse_ws_url(read_io, timeout, pid)
        output = ""
        start = Utils::ElapsedTime.monotonic_time
        max_time = start + timeout
        regexp = %r{DevTools listening on (ws://.*)}
        counter = 1
        @logger&.puts("Attemping to detect websocket for chrome (#{pid})")
        while (now = Utils::ElapsedTime.monotonic_time) < max_time
          @logger&.puts("Listening for websocket loop: #{counter} [#{now}]\n")
          counter += 1
          log_chrome_ps(pid)
          chunk = read_io.gets(512)
          if chunk.nil?
            @logger&.puts("No new IO stream output from chrome (#{pid}). Retrying ...\n")
            read_io.wait_readable(max_time - now)
          else
            @logger&.puts("chrome (#{pid}) IO stream output:\n#{chunk}\n***\n")
            output += chunk
          end

          if output.match(regexp)
            self.ws_url = output.match(regexp)[1].strip
            @logger&.puts("\nwebsocket detected for chrome (#{pid}): #{self.ws_url}")
            @logger&.puts("Chrome (#{pid}) is ready")
            break
          end
        end

        return if ws_url

        log_chrome_ps(pid, "\nNo websocket detected for chrome")
        @logger&.puts("chrome (#{pid}) IO stream output: #{output}***\n")
        raise ProcessTimeoutError.new(timeout, output)
      end

      def ws_url=(url)
        @ws_url = Addressable::URI.parse(url)
        @host = @ws_url.host
        @port = @ws_url.port
      end

      def parse_browser_versions
        return unless ws_url.is_a?(Addressable::URI)

        version_url = URI.parse(ws_url.merge(scheme: "http", path: "/json/version"))
        response = JSON.parse(::Net::HTTP.get(version_url))

        @v8_version = response["V8-Version"]
        @browser_version = response["Browser"]
        @webkit_version = response["WebKit-Version"]
        @default_user_agent = response["User-Agent"]
        @protocol_version = response["Protocol-Version"]
      end

      def close_io(*ios)
        ios.each do |io|
          io.close unless io.closed?
        rescue IOError
          raise unless RUBY_ENGINE == "jruby"
        end
      end

      def log_chrome_ps(pid, message="chrome")
        @logger&.puts("#{message} (#{pid}):\n #{`ps #{pid}`}\n")
      end
    end
  end
end
