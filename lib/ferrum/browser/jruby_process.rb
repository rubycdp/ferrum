# frozen_string_literal: true

require "ferrum/browser/process"

module Ferrum
  class Browser
    class JrubyProcess < Process
      def start
        # Don't do anything as browser is already running as external process.
        return if ws_url

        begin
          process_builder = java.lang.ProcessBuilder.new(*@command.to_a)
          # unless user directory is on a Windows UNC path
          process_builder.directory(java.io.File.new(@user_data_dir)) unless @user_data_dir =~ %r{\A//}
          process_builder.redirectErrorStream(true)

          if @command.xvfb?
            @xvfb = Xvfb.start(@command.options)
            ObjectSpace.define_finalizer(self, self.class.process_killer(@xvfb.pid))
            process_builder.environment.merge! Hash(@xvfb&.to_env)
          end

          process = process_builder.start
          @pid = process.pid

          @input_reader = java.io.BufferedReader.new(java.io.InputStreamReader.new(process.getInputStream))
          parse_ws_url(@input_reader, @process_timeout)
          parse_json_version(ws_url)
        end
      end

      private

      def parse_ws_url(read_io, timeout)
        output = ""
        start = Utils::ElapsedTime.monotonic_time
        max_time = start + timeout
        regexp = %r{DevTools listening on (ws://.*[a-zA-Z0-9-]{36})}
        while Utils::ElapsedTime.monotonic_time < max_time
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
    end
  end
end
