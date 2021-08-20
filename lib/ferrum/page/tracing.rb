# frozen_string_literal: true

module Ferrum
  class Page
    class Tracing
      INCLUDED_CATEGORIES = %w[
        devtools.timeline
        v8.execute
        disabled-by-default-devtools.timeline
        disabled-by-default-devtools.timeline.frame
        toplevel
        blink.console
        blink.user_timing
        latencyInfo
        disabled-by-default-devtools.timeline.stack
        disabled-by-default-v8.cpu_profiler
        disabled-by-default-v8.cpu_profiler.hires
      ].freeze
      EXCLUDED_CATEGORIES = %w[
        *
      ].freeze

      def initialize(client:)
        @client = client
      end

      def record(options = {}, &block)
        @options = {
          timeout: nil,
          screenshots: false,
          encoding: :binary,
          included_categories: INCLUDED_CATEGORIES,
          excluded_categories: EXCLUDED_CATEGORIES,
          **options
        }
        @promise = Concurrent::Promises.resolvable_future
        subscribe_on_tracing_event
        start
        block.call
        @client.command("Tracing.end")
        @promise.value!(@options[:timeout])
      end

      private

      def start
        @client.command(
          "Tracing.start",
          transferMode: "ReturnAsStream",
          traceConfig: {
            includedCategories: included_categories,
            excludedCategories: @options[:excluded_categories]
          }
        )
      end

      def included_categories
        included_categories = @options[:included_categories]
        if @options[:screenshots] == true
          included_categories = @options[:included_categories] | ["disabled-by-default-devtools.screenshot"]
        end
        included_categories
      end

      def subscribe_on_tracing_event
        @client.on("Tracing.tracingComplete") do |event, index|
          next if index.to_i != 0

          @promise.fulfill(stream(event.fetch("stream")))
        rescue StandardError => e
          @promise.reject(e)
        end
      end

      def stream(handle)
        Utils::Stream.fetch(encoding: @options[:encoding], path: @options[:path]) do |read_stream|
          read_stream.call(client: @client, handle: handle)
        end
      end
    end
  end
end
