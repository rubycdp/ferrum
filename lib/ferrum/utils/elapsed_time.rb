# frozen_string_literal: true

module Ferrum
  module Utils
    #
    # A monotonic-clock helper for tracking elapsed time and checking
    # timeouts, backed by `Concurrent.monotonic_time`.
    #
    module ElapsedTime
      module_function

      #
      # Sets the start point to the current monotonic time unless already set.
      #
      # @return [Float]
      #
      def start
        @start ||= monotonic_time
      end

      #
      # Resets the start point to the current monotonic time.
      #
      # @return [Float]
      #
      def reset
        @start = monotonic_time
      end

      #
      # Returns the time elapsed since `start` (or since {.start}/{.reset} was called).
      #
      # @param [Float, nil] start
      #   Monotonic time to measure from, defaults to the stored start point.
      #
      # @return [Float]
      #
      def elapsed_time(start = nil)
        monotonic_time - (start || @start)
      end

      #
      # Returns the current monotonic clock time in seconds.
      #
      # @return [Float]
      #
      def monotonic_time
        Concurrent.monotonic_time
      end

      #
      # Whether more than `timeout` seconds have elapsed since `start`.
      #
      # @param [Float] start
      #   Monotonic time to measure from.
      #
      # @param [Float, Integer] timeout
      #   The timeout, in seconds.
      #
      # @return [Boolean]
      #
      def timeout?(start, timeout)
        elapsed_time(start) > timeout
      end
    end
  end
end
