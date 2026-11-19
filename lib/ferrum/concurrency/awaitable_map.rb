# frozen_string_literal: true

module Ferrum
  module Concurrency
    #
    # A thread-safe hash that threads can wait on: {#await} returns the value of a key as soon as it is stored, at
    # once if it already is, so it doesn't matter whether the waiter or the writer comes first.
    #
    # A writer that only answers waiters, like a response to a command that may have nobody waiting, uses
    # {#expect} on the waiting side and {#fulfill} on the writing side: values nobody expects are dropped.
    #
    # @example
    #   map = Ferrum::Concurrency::AwaitableMap.new
    #   Thread.new { map["a"] = 1 }
    #   map.await("a", 5) # => 1
    #
    class AwaitableMap
      def initialize
        @mutex = Mutex.new
        @condition = ConditionVariable.new
        @map = {}
        @expected = {}
        @closed = false
      end

      #
      # @param [Object] key
      #
      # @return [Object, nil]
      #
      def [](key)
        @mutex.synchronize { @map[key] }
      end

      #
      # Stores the value and wakes the threads waiting for the key.
      #
      # @param [Object] key
      #
      # @param [Object] value
      #
      # @return [Object]
      #
      def []=(key, value)
        @mutex.synchronize do
          @map[key] = value
          @condition.broadcast
        end
        value
      end

      #
      # Announces that a thread is going to wait for the key, so {#fulfill} keeps its value.
      #
      # @param [Object] key
      #
      # @return [Object]
      #   The key.
      #
      def expect(key)
        @mutex.synchronize { @expected[key] = true }
        key
      end

      #
      # @param [Object] key
      #
      # @return [Boolean]
      #
      def expecting?(key)
        @mutex.synchronize { @expected.key?(key) }
      end

      #
      # Stores the value and wakes the waiters, only if the key was expected.
      #
      # @param [Object] key
      #
      # @param [Object] value
      #
      # @return [Boolean]
      #   Whether the value was stored.
      #
      def fulfill(key, value)
        @mutex.synchronize do
          next false unless @expected.key?(key)

          @map[key] = value
          @condition.broadcast
          true
        end
      end

      #
      # Removes the key and the expectation of it.
      #
      # @param [Object] key
      #
      # @return [Object, nil]
      #   The removed value.
      #
      def delete(key)
        @mutex.synchronize do
          @expected.delete(key)
          @map.delete(key)
        end
      end

      #
      # Wakes every waiter for good: once closed, {#await} doesn't block and returns what is stored.
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
      # @param [Object] key
      #
      # @return [Boolean]
      #
      def key?(key)
        @mutex.synchronize { @map.key?(key) }
      end

      #
      # @return [Hash]
      #   A copy of the stored pairs.
      #
      def to_h
        @mutex.synchronize { @map.dup }
      end

      #
      # @return [Array<Object>]
      #
      def values
        @mutex.synchronize { @map.values }
      end

      #
      # Blocks until the key is stored or the timeout is reached.
      #
      # @param [Object] key
      #
      # @param [Numeric, Deadline] timeout
      #
      # @return [Object, nil]
      #   The value, `nil` when the timeout is reached.
      #
      def await(key, timeout)
        deadline = Deadline.wrap(timeout)
        @mutex.synchronize do
          @condition.wait(@mutex, deadline.remaining) until @map.key?(key) || @closed || deadline.expired?
          @map[key]
        end
      end

      #
      # @return [String]
      #
      def inspect
        @mutex.synchronize { @map.inspect }
      end
    end
  end
end
