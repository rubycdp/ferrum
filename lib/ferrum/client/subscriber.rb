# frozen_string_literal: true

module Ferrum
  class Client
    #
    # Dispatches incoming CDP events to registered callbacks. Messages are
    # queued and processed on dedicated threads, with `Fetch.requestPaused`
    # and `Fetch.authRequired` given priority so request interception isn't
    # delayed behind other events.
    #
    class Subscriber
      INTERRUPTIONS = %w[Fetch.requestPaused Fetch.authRequired].freeze

      def initialize
        @regular = Queue.new
        @priority = Queue.new
        @on = Concurrent::Hash.new

        start
      end

      #
      # Enqueues an incoming CDP message for dispatch to subscribers.
      # `Fetch.requestPaused`/`Fetch.authRequired` messages jump the regular
      # queue so request interception isn't delayed behind other events.
      #
      # @param [Hash] message
      #   The raw CDP message, as parsed from the websocket.
      #
      # @return [void]
      #
      def <<(message)
        if INTERRUPTIONS.include?(message["method"])
          @priority.push(message)
        else
          @regular.push(message)
        end
      end

      #
      # Registers a callback for a CDP event.
      #
      # @param [String] event
      #   The event key, as built by {SessionClient.event_name}.
      #
      # @return [Integer]
      #   The callback's index within the event's callback list, used to
      #   unsubscribe via {#off}.
      #
      def on(event, &block)
        @on[event] ||= Concurrent::Array.new
        @on[event] << block
        @on[event].index(block)
      end

      #
      # Unregisters a callback for a CDP event.
      #
      # @param [String] event
      #   The event key, as built by {SessionClient.event_name}.
      #
      # @param [Integer] id
      #   The callback's index, as returned by {#on}.
      #
      # @return [Boolean]
      #
      def off(event, id)
        @on[event].delete_at(id)
        true
      end

      #
      # Whether there's at least one callback registered for the event.
      #
      # @param [String] event
      #   The event key, as built by {SessionClient.event_name}.
      #
      # @return [Boolean]
      #
      def subscribed?(event)
        @on.key?(event)
      end

      #
      # Stops the regular and priority dispatch threads.
      #
      # @return [void]
      #
      def close
        @regular_thread&.kill
        @priority_thread&.kill
      end

      #
      # Removes all callbacks registered for a given session.
      #
      # @param [String] session_id
      #   The session id to match against registered event keys.
      #
      # @return [void]
      #
      def clear(session_id:)
        @on.delete_if { |k, _| k.match?(session_id) }
      end

      private

      def start
        @regular_thread = Utils::Thread.spawn(abort_on_exception: false) do
          loop do
            message = @regular.pop
            break unless message

            call(message)
          end
        end

        @priority_thread = Utils::Thread.spawn(abort_on_exception: false) do
          loop do
            message = @priority.pop
            break unless message

            call(message)
          end
        end
      end

      def call(message)
        method, session_id, params = message.values_at("method", "sessionId", "params")
        event = SessionClient.event_name(method, session_id)

        total = @on[event]&.size.to_i
        @on[event]&.each_with_index do |block, index|
          # In case of multiple callbacks we provide current index and total
          block.call(params, index, total)
        end
      end
    end
  end
end
