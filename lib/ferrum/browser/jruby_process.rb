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
          output_file = File.expand_path("chrome_output.log", @user_data_dir)
          process_builder.redirectOutput(java.lang.ProcessBuilder::Redirect.appendTo(java.io.File.new(output_file)))

          environment = process_builder.environment
          # Clear the environment to avoid setting e.g. RUBYOPT from the initial environment
          environment.clear

          if @command.xvfb?
            @xvfb = Xvfb.start(@command.options)
            ObjectSpace.define_finalizer(self, self.class.process_killer(@xvfb.pid))
            environment.merge! Hash(@xvfb&.to_env)
          end

          @process = process_builder.start
          @pid = @process.pid

          parse_ws_url(output_file, @process_timeout)
          parse_json_version(ws_url)
        end
      rescue IOError
        # nop
      end

      private

      def parse_ws_url(output_file, timeout)
        output = ""
        start = Utils::ElapsedTime.monotonic_time
        max_time = start + timeout
        regexp = %r{DevTools listening on (ws://.*)}
        while Utils::ElapsedTime.monotonic_time < max_time
          File.open(output_file, "r+") do |file|
            file.each_line { |line| output += line }
            file.truncate(0)
            file.rewind

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
    end
  end
end
