# frozen_string_literal: true

module Ferrum
  class Page
    class Tracing
      EXCLUDED_CATEGORIES = %w[*].freeze
      SCREENSHOT_CATEGORIES = %w[disabled-by-default-devtools.screenshot].freeze
      INCLUDED_CATEGORIES = %w[devtools.timeline v8.execute disabled-by-default-devtools.timeline
                               disabled-by-default-devtools.timeline.frame toplevel blink.console
                               blink.user_timing latencyInfo disabled-by-default-devtools.timeline.stack
                               disabled-by-default-v8.cpu_profiler disabled-by-default-v8.cpu_profiler.hires].freeze
      DEFAULT_TRACE_CONFIG = {
        includedCategories: INCLUDED_CATEGORIES,
        excludedCategories: EXCLUDED_CATEGORIES
      }.freeze

      def initialize(page)
        @page = page
        @subscribed_tracing_complete = false
      end

      def record(path: nil, encoding: :binary, timeout: nil, trace_config: nil, screenshots: false)
        @path, @encoding = path, encoding
        @result = Concurrent::Promises.resolvable_future
        trace_config ||= DEFAULT_TRACE_CONFIG.dup

        if screenshots
          included = trace_config.fetch(:includedCategories, [])
          trace_config.merge!(includedCategories: included | SCREENSHOT_CATEGORIES)
        end

        subscribe_tracing_complete

        start(trace_config)
        yield
        stop

        @result.value!(timeout)
      end

      private

      def start(config)
        @page.command("Tracing.start", transferMode: "ReturnAsStream", traceConfig: config)
      end

      def stop
        @page.command("Tracing.end")
      end

      def subscribe_tracing_complete
        return if @subscribed_tracing_complete

        @page.on("Tracing.tracingComplete") do |event, index|
          next if index.to_i != 0
          @result.fulfill(stream_handle(event["stream"]))
        rescue => e
          @result.reject(e)
        end

        @subscribed_tracing_complete = true
      end

      def stream_handle(handle)
        @page.stream_to(path: @path, encoding: @encoding, handle: handle)
      end
    end
  end
end
