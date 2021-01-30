# frozen_string_literal: true

require "cliver"
require "net/http"
require "json"
require "addressable"
require "tmpdir"
require "forwardable"
require "ferrum/browser/options/base"
require "ferrum/browser/options/chrome"
require "ferrum/browser/options/firefox"
require "ferrum/browser/command"

module Ferrum
  class Browser
    class Process
      KILL_TIMEOUT = 2
      WAIT_KILLED = 0.05
      PROCESS_TIMEOUT = ENV.fetch("FERRUM_PROCESS_TIMEOUT", 2).to_i

      attr_reader :host, :port, :ws_url, :pid, :command,
                  :default_user_agent, :browser_version, :protocol_version,
                  :v8_version, :webkit_version, :xvfb


      extend Forwardable
      delegate path: :command

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
        proc { FileUtils.remove_entry(path) rescue Errno::ENOENT }
      end

      def initialize(options)
        if options[:url]
          url = URI.join(options[:url].to_s, "/json/version")
          response = JSON.parse(::Net::HTTP.get(url))
          set_ws_url(response["webSocketDebuggerUrl"])
          parse_browser_versions
          return
        end

        @logger = options[:logger]
        @process_timeout = options.fetch(:process_timeout, PROCESS_TIMEOUT)

        tmpdir = Dir.mktmpdir("ferrum_user_data_dir_")
        ObjectSpace.define_finalizer(self, self.class.directory_remover(tmpdir))
        @user_data_dir = tmpdir
        @command = Command.build(options, tmpdir)
      end

      def start
        # Don't do anything as browser is already running as external process.
        return if ws_url

        begin
          read_io, write_io = IO.pipe
          process_options = { in: File::NULL }
          process_options[:pgroup] = true unless Ferrum.windows?
          process_options[:out] = process_options[:err] = write_io

          if @command.xvfb?
            @xvfb = Xvfb.start(@command.options)
            ObjectSpace.define_finalizer(self, self.class.process_killer(@xvfb.pid))
          end

          @pid = ::Process.spawn(Hash(@xvfb&.to_env), *@command.to_a, process_options)
          ObjectSpace.define_finalizer(self, self.class.process_killer(@pid))

          parse_ws_url(read_io, @process_timeout)
          parse_browser_versions
        ensure
          close_io(read_io, write_io)
        end
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
        self.class.process_killer(pid).call
      end

      def remove_user_data_dir
        self.class.directory_remover(@user_data_dir).call
        @user_data_dir = nil
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
          @logger.puts(output) if @logger
          raise ProcessTimeoutError.new(timeout, output)
        end
      end

      def set_ws_url(url)
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
