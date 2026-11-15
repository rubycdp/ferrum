# frozen_string_literal: true

module Ferrum
  module Utils
    #
    # A thread-safe slot that threads wait on: it holds a value once set, can be cleared and set again, and wakes
    # every waiter when it is set or closed. It serves as a one-shot response, the latest value of something that
    # changes, or a latch, and every wait is bounded by a {Deadline}.
    #
    # @example
    #   cell = Ferrum::Utils::Cell.new
    #   Thread.new { cell.set(42) }
    #   cell.wait(5) # => true
    #   cell.value   # => 42
    #
    class Cell
      # How many times the cell has been cleared.
      #
      # @return [Integer]
      attr_reader :generation

      #
      # Builds a cell that already holds the value.
      #
      # @param [Object] value
      #
      # @return [Cell]
      #
      def self.set(value)
        new.tap { |c| c.set(value) }
      end

      def initialize
        @mutex = Mutex.new
        @condition = ConditionVariable.new
        @set = false
        @closed = false
        @value = nil
        @generation = 0
      end

      #
      # Stores the value and wakes the waiters.
      #
      # @param [Object] value
      #
      # @return [Object]
      #
      def set(value)
        @mutex.synchronize do
          @value = value
          @set = true
          @condition.broadcast
        end
        value
      end

      #
      # Empties the cell and counts it as a new generation.
      #
      # @return [Integer]
      #   The new generation.
      #
      def clear
        @mutex.synchronize do
          @value = nil
          @set = false
          @generation += 1
        end
      end

      #
      # Whether a value is stored.
      #
      # @return [Boolean]
      #
      def set?
        @mutex.synchronize { @set }
      end

      #
      # The stored value, `nil` when the cell is empty.
      #
      # @return [Object, nil]
      #
      def value
        @mutex.synchronize { @value }
      end

      #
      # Wakes the waiters for good: a closed cell never blocks, so a waiter learns at once that nothing is coming.
      #
      # @return [void]
      #
      def close
        @mutex.synchronize do
          @closed = true
          @condition.broadcast
        end
      end

      #
      # Whether the cell is closed.
      #
      # @return [Boolean]
      #
      def closed?
        @mutex.synchronize { @closed }
      end

      #
      # Blocks until a value is stored, the cell is closed or the timeout is reached.
      #
      # @param [Numeric, Deadline] timeout
      #
      # @return [Boolean]
      #   Whether a value is stored.
      #
      def wait(timeout)
        deadline = Deadline.wrap(timeout)
        @mutex.synchronize do
          @condition.wait(@mutex, deadline.remaining) until @set || @closed || deadline.expired?
          @set
        end
      end
    end
  end
end
