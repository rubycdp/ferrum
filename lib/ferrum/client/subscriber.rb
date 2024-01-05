# frozen_string_literal: true

module Ferrum
  class Client
    class Subscriber
      INTERRUPTIONS = %w[Fetch.requestPaused Fetch.authRequired].freeze

      def initialize
        @regular = Queue.new
        @priority = Queue.new
        @on = Concurrent::Hash.new { |h, k| h[k] = Concurrent::Array.new }

        start
      end

      def <<(message)
        if INTERRUPTIONS.include?(message["method"])
          @priority.push(message)
        else
          @regular.push(message)
        end
      end

      def on(event, &block)
        @on[event] << block
        true
      end

      def subscribed?(event)
        @on.key?(event)
      end

      def close
        @regular_thread&.kill
        @priority_thread&.kill
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
        method, params = message.values_at("method", "params")
        total = @on[method].size
        @on[method].each_with_index do |block, index|
          # In case of multiple callbacks we provide current index and total
          block.call(params, index, total)
        end
      end
    end
  end
end
