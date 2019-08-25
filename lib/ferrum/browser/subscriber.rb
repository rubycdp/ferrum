# frozen_string_literal: true

require "concurrent-ruby"

module Ferrum
  class Browser
    class Subscriber
      include Concurrent::Async

      def initialize
        super
        @on = Hash.new { |h, k| h[k] = [] }
      end

      def on(event, &block)
        @on[event] << block
        true
      end

      def call(message)
        method, params = message.values_at("method", "params")
        @on[method].each { |b| b.call(params) }
      end
    end
  end
end
