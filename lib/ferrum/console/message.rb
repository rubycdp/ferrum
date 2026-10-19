# frozen_string_literal: true

require "json"
require "ferrum/console/location"

module Ferrum
  class Console
    #
    # A message as the DevTools console would show it: a `console.*` call,
    # a browser log entry (failed resource loads, CSP violations,
    # deprecations, ...) or an uncaught exception. The text, arguments and
    # stack trace are only converted from CDP when asked for.
    #
    class Message
      SEVERITIES = { error: :error, assert: :error, warning: :warn,
                     debug: :debug, verbose: :debug, trace: :debug }.freeze
      UNSERIALIZABLE = { "NaN" => Float::NAN, "Infinity" => Float::INFINITY,
                         "-Infinity" => -Float::INFINITY, "-0" => -0.0 }.freeze

      # What logged the message: `:log`, `:info`, `:warning`, `:error`,
      # `:debug`, `:table`, `:trace`, `:assert`, ... for `console.*` calls,
      # `:verbose`, `:info`, `:warning` or `:error` for browser log entries
      # and `:error` for uncaught exceptions.
      #
      # @return [Symbol]
      attr_reader :type

      # Where the message comes from: `:console_api` for `console.*` calls,
      # `:exception` for uncaught exceptions, otherwise the browser log
      # entry's source such as `:network`, `:security`, `:violation`,
      # `:deprecation` or `:intervention`.
      #
      # @return [Symbol]
      attr_reader :source

      # When the message was logged.
      #
      # @return [Time]
      attr_reader :timestamp

      # Builds a message from `Runtime.consoleAPICalled` params.
      #
      # @param [Hash{String => Object}] params
      #
      # @return [Message]
      def self.from_console_api(params)
        new(type: params["type"], source: "console_api", timestamp: params["timestamp"],
            raw_args: params["args"], frames: params.dig("stackTrace", "callFrames"))
      end

      # Builds a message from a `Log.entryAdded` entry.
      #
      # @param [Hash{String => Object}] entry
      #
      # @return [Message]
      def self.from_log_entry(entry)
        frames = entry.dig("stackTrace", "callFrames")
        frames ||= [entry.slice("url", "lineNumber")] if entry["url"]
        new(type: entry["level"], source: entry["source"], timestamp: entry["timestamp"],
            raw_text: entry["text"], frames: frames)
      end

      # Builds a message from `Runtime.exceptionThrown` params.
      #
      # @param [Hash{String => Object}] params
      #
      # @return [Message]
      def self.from_exception(params)
        details = params["exceptionDetails"]
        frames = details.dig("stackTrace", "callFrames")
        frames ||= [details.slice("url", "lineNumber", "columnNumber")]
        text = [details["text"], details.dig("exception", "description")].compact.uniq.join(" ")
        new(type: "error", source: "exception", timestamp: params["timestamp"], raw_text: text, frames: frames)
      end

      def initialize(type:, source:, timestamp:, raw_args: nil, raw_text: nil, frames: nil)
        @type = underscore(type)
        @source = underscore(source)
        @timestamp = Time.at(0, timestamp.to_f, :millisecond)
        @raw_args = raw_args || []
        @raw_text = raw_text
        @frames = frames || []
      end

      # The message text. `console.*` arguments are joined by spaces, with
      # objects and arrays rendered as JSON.
      #
      # @return [String]
      def text
        @text ||= @raw_text || @raw_args.map { |arg| arg_text(arg) }.join(" ")
      end

      # The `console.*` arguments as Ruby values. Strings, numbers,
      # booleans and `null` come as they are, `undefined` is `nil`, plain
      # objects and arrays are a `Hash` or an `Array` built from Chrome's
      # shallow preview, anything else (functions, DOM nodes, errors, ...) is
      # its description. Empty for log entries and exceptions.
      #
      # @return [Array<Object>]
      def args
        @args ||= @raw_args.map { |arg| arg_value(arg) }
      end

      # The call stack at the moment the message was logged, innermost frame
      # first. Can be empty.
      #
      # @return [Array<Location>]
      def stack_trace
        @stack_trace ||= @frames.map { |frame| Location.from_frame(frame) }
      end

      # Where the message was logged from.
      #
      # @return [Location, nil]
      def location
        stack_trace.first
      end

      # The {#type} expressed as a `Logger` method name, so a message can be
      # passed on with `logger.public_send(message.severity, message)`.
      #
      # @return [Symbol]
      #   `:debug`, `:info`, `:warn` or `:error`.
      def severity
        SEVERITIES.fetch(type, :info)
      end

      # Whether the message is an error: `console.error`, a failed
      # `console.assert`, an error log entry or an uncaught exception.
      #
      # @return [Boolean]
      def error?
        severity == :error
      end

      # Whether the message is a warning.
      #
      # @return [Boolean]
      def warning?
        severity == :warn
      end

      # Whether the message text matches the given pattern.
      #
      # @param [Regexp, String] pattern
      #   A regexp matched against the text, or a string checked for inclusion in it.
      #
      # @return [Boolean]
      def match?(pattern)
        return text.match?(pattern) if pattern.is_a?(Regexp)

        text.include?(pattern.to_s)
      end

      # The message as the logger prints it: `[type] text`, followed by an
      # `at function (url:line:column)` line per stack frame.
      #
      # @return [String]
      def to_s
        lines = stack_trace.map { |frame| "    at #{frame.function_name} (#{frame})" }
        ["[#{type}] #{text}", *lines].join("\n")
      end

      # Debug representation of the message.
      #
      # @return [String]
      def inspect
        "#<#{self.class.name} type=#{type.inspect} source=#{source.inspect} text=#{text.inspect}>"
      end

      private

      def underscore(name)
        name.to_s.gsub(/(?<=[a-z])(?=[A-Z])|-/, "_").downcase.to_sym
      end

      def arg_text(arg)
        value = arg_value(arg)

        case value
        when String then value
        when Hash, Array then JSON.generate(value)
        when nil then arg["subtype"] == "null" ? "null" : "undefined"
        else arg["description"] || value.to_s
        end
      end

      def arg_value(arg)
        return arg["value"] if arg.key?("value")
        return unserializable(arg["unserializableValue"]) if arg.key?("unserializableValue")
        return if arg["type"] == "undefined"

        preview_value(arg["preview"]) || arg["description"]
      end

      def preview_value(preview)
        return unless preview && preview["type"] == "object"

        case preview["subtype"]
        when nil then preview["properties"].to_h { |property| [property["name"], property_value(property)] }
        when "array" then preview["properties"].map { |property| property_value(property) }
        end
      end

      def property_value(property)
        return preview_value(property["valuePreview"]) || property["value"] if property["valuePreview"]

        value = property["value"]
        case property["type"]
        when "number" then parse_number(value)
        when "bigint" then unserializable(value)
        when "boolean" then value == "true"
        when "undefined" then nil
        when "object" then property["subtype"] == "null" ? nil : value
        else value
        end
      end

      def unserializable(value)
        UNSERIALIZABLE.fetch(value) { value.end_with?("n") ? Integer(value.delete_suffix("n")) : value }
      end

      def parse_number(value)
        return UNSERIALIZABLE[value] if UNSERIALIZABLE.key?(value)

        Integer(value, exception: false) || Float(value, exception: false) || value
      end
    end
  end
end
