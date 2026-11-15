# frozen_string_literal: true

module Ferrum
  module Interceptable
    #
    # An ordered chain of handlers for an event that has to be answered
    # exactly once, e.g. a paused request or a dialog. Handlers run in the
    # order they were added and the chain stops at the first one that handles
    # the event object, so a handler that doesn't want the object just
    # returns. An object nobody handled is passed to the default action.
    #
    class Chain
      # @param [#on, #off] client
      #   Where the event comes from.
      #
      # @param [String] event
      #   The CDP event name.
      #
      # @param [#call] build
      #   Turns the event params into the object handlers receive. The object
      #   has to respond to `handled?`.
      #
      # @param [#call] default
      #   Called with the object when no handler handled it.
      #
      # @param [Boolean] persistent
      #   Keep listening to the event while no handlers are left, so the
      #   default action still applies.
      def initialize(client, event, build:, default:, persistent: false)
        @client = client
        @event = event
        @build = build
        @default = default
        @handlers = Concurrent::Hash.new
        @sequence = Concurrent::AtomicFixnum.new
        @subscription = nil
        @persistent = persistent
        @mutex = Mutex.new
        @mutex.synchronize { subscribe } if persistent
      end

      #
      # Adds a handler to the end of the chain.
      #
      # @return [Integer]
      #   The id to pass to {#remove}.
      #
      def add(&block)
        id = @sequence.increment
        @mutex.synchronize do
          @handlers[id] = block
          subscribe
        end
        id
      end

      #
      # Removes a handler, and stops listening to the event once no handlers
      # are left.
      #
      # @param [Integer] id
      #   The id returned by {#add}.
      #
      # @return [void]
      #
      def remove(id)
        @mutex.synchronize do
          @handlers.delete(id)
          next if @persistent || @handlers.any? || @subscription.nil?

          @client.off(@event, @subscription)
          @subscription = nil
        end
      end

      private

      def subscribe
        @subscribe ||= @client.on(@event) { |params| run(params) }
      end

      def run(params)
        object = @build.call(params)
        @handlers.each_value do |handler|
          break if object.handled?

          call(handler, object)
        end
        @default.call(object) unless object.handled?
      end

      def call(handler, object)
        handler.call(object)
      rescue StandardError => e
        warn("Ferrum: #{@event} callback raised #{e.class}: #{e.message}\n  #{e.backtrace&.first}")
      end
    end
  end
end
