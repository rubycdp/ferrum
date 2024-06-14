# frozen_string_literal: true

require "ferrum/browser/process"

module Ferrum
  class Browser
    class JrubyProcess < Process
      def start
        # Don't do anything as browser is already running as external process.
        return if ws_url

        begin
          process_builder_args = @command.to_a
          # Sometimes subprocesses are launched with the wrong architecture on Apple Silicon.
          if ENV_JAVA['os.name'] == 'Mac OS X' && ENV_JAVA['os.arch'] == 'aarch64'
            process_builder_args.unshift('/usr/bin/arch', '-arm64')
          end
          process_builder = java.lang.ProcessBuilder.new(*process_builder_args)
          # unless user directory is on a Windows UNC path
          process_builder.directory(java.io.File.new(@user_data_dir)) unless @user_data_dir =~ %r{\A//}
          process_builder.redirectErrorStream(true)

          if @command.xvfb?
            @xvfb = Xvfb.start(@command.options)
            ObjectSpace.define_finalizer(self, self.class.process_killer(@xvfb.pid))
            process_builder.environment.merge! Hash(@xvfb&.to_env)
          end

          @java_process = process_builder.start

          # The process output is switched to a buffered reader and parsed to get the WebSocket URL.
          input_reader = java.io.BufferedReader.new(java.io.InputStreamReader.new(java_process.getInputStream))
          parse_ws_url(input_reader, @process_timeout)
          parse_json_version(ws_url)
        end
      end

      attr_reader :java_process

      def stop
        destroy_java_process

        remove_user_data_dir if @user_data_dir
        ObjectSpace.undefine_finalizer(self)
      end

      private

      def parse_ws_url(read_io, timeout)
        output = ""
        start = Utils::ElapsedTime.monotonic_time
        max_time = start + timeout
        regexp = %r{DevTools listening on (ws://.*[a-zA-Z0-9-]{36})}
        while Utils::ElapsedTime.monotonic_time < max_time
          # The buffered reader is used to read the process output.
          if output.match(regexp)
            self.ws_url = output.match(regexp)[1].strip
            break
          elsif (rl = read_io.read_line)
            output += rl
          end
        end

        return if ws_url

        @logger&.puts(output)
        raise ProcessTimeoutError.new(timeout, output)
      end

      def destroy_java_process(options = {})
        if java_process
          java_process.destroy
          retry_times = 6
          while java_process.isAlive && retry_times > 0
            sleep 1
            retry_times -= 1
          end
          if java_process.isAlive
            @logger&.puts("Ferrum::Browser::JrubyProcess is still alive, killing it forcibly")
            java_process.destroyForcibly
          else
            @logger&.puts("Ferrum::Browser::JrubyProcess is stopped")
          end
          @java_process = nil
        end
      end
    end
  end
end
