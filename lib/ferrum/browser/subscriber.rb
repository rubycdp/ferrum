# frozen_string_literal: true

require "concurrent-ruby"

module Ferrum
  class Browser
    class Subscriber
      include Concurrent::Async

      def self.build(size)
        (0..size).map { new }
      end

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
        total = @on[method].size
        @on[method].each_with_index do |block, index|
          # If there are a few callback we provide current index and total
          block.call(params, index, total)
        end
      end
    end
  end
end
