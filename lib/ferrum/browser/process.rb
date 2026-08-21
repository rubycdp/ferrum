# frozen_string_literal: true

require "net/http"
require "json"
require "addressable"
require "tmpdir"
require "forwardable"
require "ferrum/browser/options/base"
require "ferrum/browser/options/chrome"
require "ferrum/browser/options/firefox"
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
      KILL_TIMEOUT = 2
      WAIT_KILLED = 0.05
      REMOVE_DIR_RETRIES = 5
      REMOVE_DIR_RETRY_DELAY = 0.1

      extend Forwardable

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

      #
      # Builds a finalizer proc that kills the process with the given pid.
      #
      # @param [Integer] pid
      #   Process id to kill.
      #
      # @return [Proc]
      #
      def self.process_killer(pid)
        proc do
          if Utils::Platform.windows?
            # Process.kill is unreliable on Windows
            ::Process.kill("KILL", pid) unless system("taskkill /f /t /pid #{pid} >NUL 2>NUL")
          else
            send_signal(pid, "TERM")
            start = Utils::ElapsedTime.monotonic_time
            leader_exited = false
            loop do
              # The leader (the pid we actually spawned and can #wait on) may
              # exit well before the rest of its process group does -- e.g. a
              # renderer/zygote that ignores TERM. Reaping the leader must not
              # by itself end the loop, or that child is orphaned forever
              # since KILL is only ever sent from the timeout branch below.
              leader_exited ||= !::Process.wait(pid, ::Process::WNOHANG).nil?
              break if leader_exited && !process_group_alive?(pid)

              sleep(WAIT_KILLED)
              next unless Utils::ElapsedTime.timeout?(start, KILL_TIMEOUT)

              send_signal(pid, "KILL")
              ::Process.wait(pid) unless leader_exited
              break
            end
          end
        rescue Errno::ESRCH, Errno::ECHILD
          # nop
        end
      end

      #
      # Signals the whole process group Chrome was spawned into (it's spawned
      # with `pgroup: true`), so its child processes (renderer, GPU, zygote,
      # ...) are cleaned up too instead of being left orphaned. Falls back to
      # signaling just the pid directly if there's no such process group to
      # signal (e.g. Xvfb, which isn't spawned with `pgroup: true`) or the
      # group can't be signaled.
      #
      # @param [Integer] pid
      # @param [String] name
      #
      # @return [void]
      #
      def self.send_signal(pid, name)
        ::Process.kill(name, -pid)
      rescue Errno::EPERM, Errno::ESRCH
        ::Process.kill(name, pid)
      end

      #
      # Checks whether any process in pid's process group is still alive.
      #
      # @param [Integer] pid
      #
      # @return [Boolean]
      #
      def self.process_group_alive?(pid)
        ::Process.kill(0, -pid)
        true
      rescue Errno::ESRCH
        false
      rescue Errno::EPERM
        true
      end

      #
      # Builds a finalizer proc that removes the directory at the given path.
      #
      # @param [String] path
      #   Directory to remove.
      #
      # @return [Proc]
      #
      def self.directory_remover(path)
        proc { remove_directory(path) }
      end

      #
      # Removes the given directory, retrying with exponential backoff on
      # transient errors. Chrome can briefly hold file locks right after
      # being killed, so the directory may not be removable on the first
      # try; retrying avoids leaking temp directories in that case.
      #
      # @param [String] path
      #   Directory to remove.
      # @param [Integer] retries
      #   Maximum number of removal attempts.
      # @param [Float] delay
      #   Base delay, in seconds, before the first retry; doubles on each
      #   subsequent attempt.
      #
      # @return [void]
      #
      def self.remove_directory(path, retries: REMOVE_DIR_RETRIES, delay: REMOVE_DIR_RETRY_DELAY)
        retries.times do |attempt|
          FileUtils.remove_entry(path)
          break
        rescue Errno::ENOENT
          break
        rescue Errno::ENOTEMPTY, Errno::EBUSY, Errno::EACCES, Errno::EPERM => e
          raise e if attempt == retries - 1

          sleep(delay * (2**attempt))
        end
      rescue StandardError => e
        warn("[Ferrum] Failed to remove user data dir #{path}: #{e.class}: #{e.message}")
      end

      attr_reader :host, :port, :ws_url, :pid, :command,
                  :default_user_agent, :browser_version, :protocol_version,
                  :v8_version, :webkit_version, :xvfb

      def initialize(options)
        @pid = @xvfb = @user_data_dir = nil

        if options.ws_url || options.url
          # `:ws_url` option is higher priority than `:url`, parse versions
          # and use it as a ws_url, otherwise use what has been parsed.
          response = parse_json_version(options.ws_url || options.url)
          self.ws_url = options.ws_url || response&.[]("webSocketDebuggerUrl")
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

          if @command.xvfb?
            @xvfb = Xvfb.start(@command.options)
            ObjectSpace.define_finalizer(self, self.class.process_killer(@xvfb.pid))
          end

          env = Hash(@xvfb&.to_env).merge(@env)
          @pid = ::Process.spawn(env, *@command.to_a, process_options)
          ObjectSpace.define_finalizer(self, self.class.process_killer(@pid))

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
      #   stubborn process group can block for up to {KILL_TIMEOUT} seconds,
      #   plus retries removing its directory, which matters when quitting
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
          kill(@pid)
          kill(@xvfb.pid) if @xvfb&.pid
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

        Utils::Thread.spawn(abort_on_exception: false) do
          kill(pid) if pid
          kill(xvfb_pid) if xvfb_pid
          self.class.remove_directory(user_data_dir) if user_data_dir
          ObjectSpace.undefine_finalizer(self)
        end
      end

      def kill(pid)
        self.class.process_killer(pid).call
      end

      def remove_user_data_dir
        self.class.remove_directory(@user_data_dir)
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
              self.ws_url = output.match(regexp)[1].strip
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

      def close_io(*ios)
        ios.each do |io|
          io.close if io && !io.closed?
        rescue IOError
          raise unless RUBY_ENGINE == "jruby"
        end
      end

      def parse_json_version(url)
        url = URI.join(url, "/json/version")

        if %w[wss ws].include?(url.scheme)
          url.scheme = case url.scheme
                       when "ws"
                         "http"
                       when "wss"
                         "https"
                       end
        end

        response = JSON.parse(::Net::HTTP.get(URI(url.to_s)))

        @v8_version = response["V8-Version"]
        @browser_version = response["Browser"]
        @webkit_version = response["WebKit-Version"]
        @default_user_agent = response["User-Agent"]
        @protocol_version = response["Protocol-Version"]

        response
      rescue JSON::ParserError
        # nop
      end
    end
  end
end
