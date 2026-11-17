# frozen_string_literal: true

module Ferrum
  module Concurrency
    #
    # Delivers published payloads to the callbacks registered for a key. Every lane is a queue with its own
    # consumer thread, so payloads of one lane are delivered in order and a slow callback never holds up another
    # lane. A raising callback is reported and doesn't stop the delivery.
    #
    # @example
    #   dispatcher = Ferrum::Concurrency::Dispatcher.new(lanes: %i[regular priority])
    #   dispatcher.on("greeting") { |payload, index, total| puts payload }
    #   dispatcher.publish("greeting", "hello", lane: :priority)
    #
    class Dispatcher
      DEFAULT_LANES = %i[regular priority].freeze

      #
      # @param [Array<Symbol>] lanes
      #   Names of the lanes, the first one is the default.
      #
      # @param [#call, nil] on_error
      #   Receives the key and the error a callback raised, warns when not given.
      #
      def initialize(lanes: DEFAULT_LANES, on_error: nil)
        @queues = lanes.to_h { |l| [l, Queue.new] }
        @on_error = on_error || method(:warn_error)
        @on = Concurrent::Hash.new
        @sequence = Concurrent::AtomicFixnum.new

        start
      end

      #
      # Enqueues a payload for delivery to the callbacks registered for the key at the time it is delivered.
      #
      # @param [String] key
      #
      # @param [Object] payload
      #
      # @param [Symbol] lane
      #   The first lane when not given.
      #
      # @return [void]
      #
      # @raise [KeyError]
      #   When there is no such lane.
      #
      def publish(key, payload, lane: @queues.each_key.first)
        @queues.fetch(lane).push([key, payload])
      end

      #
      # Registers a callback for a key. It receives the payload, its own index among the callbacks of the key and
      # their total number.
      #
      # @param [String] key
      #
      # @return [Integer]
      #   The callback's id, used to unsubscribe via {#off}. Ids are never reused, so removing a callback doesn't
      #   change the others'.
      #
      def on(key, &block)
        id = @sequence.increment
        @on[key] ||= Concurrent::Array.new
        @on[key] << [id, block]
        id
      end

      #
      # Unregisters a callback.
      #
      # @param [String] key
      #
      # @param [Integer] id
      #   The callback's id, as returned by {#on}.
      #
      # @return [Boolean]
      #
      def off(key, id)
        @on[key]&.delete_if { |i, _| i == id }
        true
      end

      #
      # Whether there's at least one callback registered for the key.
      #
      # @param [String] key
      #
      # @return [Boolean]
      #
      def subscribed?(key)
        @on[key].to_a.any?
      end

      #
      # Stops the consumer threads.
      #
      # @return [void]
      #
      def close
        @threads.each(&:kill)
      end

      #
      # Removes the callbacks of every key the block returns a truthy value for.
      #
      # @yieldparam [String] key
      #
      # @return [void]
      #
      def clear
        @on.delete_if { |k, _| yield(k) }
      end

      private

      def start
        @threads = @queues.values.map do |queue|
          Utils::Thread.spawn do
            loop do
              item = queue.pop
              break unless item

              call(*item)
            end
          end
        end
      end

      def call(key, payload)
        total = @on[key]&.size.to_i
        @on[key]&.each_with_index do |(_, block), index|
          block.call(payload, index, total)
        rescue StandardError => e
          # A raising callback used to terminate the dispatch thread, and with it every
          # event for the rest of the browser's life: targets stopped being registered
          # and any page created later raised `NoSuchTargetError`. Report and carry on.
          @on_error.call(key, e)
        end
      end

      def warn_error(key, error)
        warn("Ferrum: #{key} callback raised #{error.class}: #{error.message}\n  #{error.backtrace&.first}")
      end
    end
  end
end
