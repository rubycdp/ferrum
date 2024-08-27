# frozen_string_literal: true

module Ferrum
  module Utils
    class Event < Concurrent::Event
      def iteration
        synchronize { @iteration }
      end

      def reset
        synchronize do
          @iteration += 1
          @set = false if @set
          @iteration
        end
      end

      def wait(timeout)
        return ::Thread.pass if timeout <= 0.1

        super
      end
    end
  end
end
