# frozen_string_literal: true

module Ferrum
  class Browser
    class Xvfb
      NOT_FOUND = "Could not find an executable for the Xvfb. Try to install " \
                  "it with your package manager"

      def self.start(*args)
        new(*args).tap(&:start)
      end

      def self.xvfb_path
        Cliver.detect("Xvfb")
      end

      attr_reader :screen_size, :display_id, :pid

      def initialize(options)
        @path = self.class.xvfb_path
        raise Cliver::Dependency::NotFound, NOT_FOUND unless @path

        @screen_size = "#{options.fetch(:window_size, [1024, 768]).join('x')}x24"
        @display_id = (Time.now.to_f * 1000).to_i % 100_000_000
      end

      def start
        @pid = ::Process.spawn("#{@path} :#{display_id} -screen 0 #{screen_size}")
        ::Process.detach(@pid)
      end

      def to_env
        { "DISPLAY" => ":#{display_id}" }
      end
    end
  end
end
