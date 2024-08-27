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
        synchronize do
          unless @set
            iteration = @iteration
            ns_wait_until(timeout) do
              iteration < @iteration || @set
              ::Thread.pass
            end
          else
            true
          end
        end
      end
    end
  end
end
