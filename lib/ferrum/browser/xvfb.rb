# frozen_string_literal: true

module Ferrum
  class Browser
    #
    # Manages an Xvfb virtual display server, letting a "headful" browser run
    # in environments without a real display (e.g. CI). Spawned by {Process}
    # when the `:xvfb` option is set, and exposes the `DISPLAY` environment
    # variable the browser process needs to attach to it.
    #
    class Xvfb
      NOT_FOUND = "Could not find an executable for the Xvfb. Try to install " \
                  "it with your package manager"

      #
      # Builds and starts a new Xvfb instance.
      #
      # @param [Array] args
      #   Arguments forwarded to {#initialize}.
      #
      # @return [Xvfb]
      #
      def self.start(*args)
        new(*args).tap(&:start)
      end

      attr_reader :screen_size, :display_id, :pid

      def initialize(options)
        @path = Binary.find("Xvfb")
        raise BinaryNotFoundError, NOT_FOUND unless @path

        @screen_size = "#{options.window_size.join('x')}x24"
        @display_id = (Time.now.to_f * 1000).to_i % 100_000_000
        @timeout = options.process_timeout
      end

      #
      # Spawns the Xvfb process on the configured display and waits until it
      # accepts connections, so a browser started right after finds the display.
      #
      # @return [void]
      #
      # @raise [Error]
      #   When Xvfb exits or isn't ready within `:process_timeout`.
      #
      def start
        reader, writer = IO.pipe
        @pid = ::Process.spawn(@path, ":#{display_id}", "-screen", "0", screen_size, "-displayfd", "1", out: writer)
        ::Process.detach(@pid)
        writer.close
        wait_for_display(reader)
      ensure
        reader&.close
        writer&.close
      end

      #
      # Environment variables needed to point the browser at this Xvfb display.
      #
      # @return [Hash{String => String}]
      #
      def to_env
        { "DISPLAY" => ":#{display_id}" }
      end

      private

      def wait_for_display(io)
        return if io.wait_readable(@timeout) && io.gets

        Process::Killer.kill(@pid)
        raise Error, "Xvfb exited or wasn't ready on display :#{display_id} within #{@timeout} seconds"
      end
    end
  end
end
