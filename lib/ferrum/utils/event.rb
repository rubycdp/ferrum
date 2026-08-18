# frozen_string_literal: true

module Ferrum
  module Utils
    #
    # A {Concurrent::Event} subclass that additionally tracks how many
    # times it has been reset, via {#iteration}.
    #
    class Event < Concurrent::Event
      #
      # Number of times the event has been reset.
      #
      # @return [Integer]
      #
      def iteration
        synchronize { @iteration }
      end

      #
      # Marks the event as unset and increments the iteration counter.
      #
      # @return [Integer]
      #
      def reset
        synchronize do
          @iteration += 1
          @set = false if @set
          @iteration
        end
      end
    end
  end
end
