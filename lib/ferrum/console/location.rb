# frozen_string_literal: true

module Ferrum
  class Console
    #
    # A place in the page's source a {Message} points at: where `console.*`
    # was called, an exception was thrown or a resource failed to load.
    # Line and column numbers are 1-based.
    #
    class Location
      attr_reader :url, :line, :column, :function_name

      # Builds a location from a CDP `Runtime.CallFrame`, or from the `url`
      # and `lineNumber` of a `Log.LogEntry`. CDP numbers lines and columns
      # from 0.
      #
      # @param [Hash{String => Object}] frame
      #
      # @return [Location]
      def self.from_frame(frame)
        new(url: frame["url"].to_s,
            line: frame["lineNumber"]&.+(1),
            column: frame["columnNumber"]&.+(1),
            function_name: frame["functionName"].to_s)
      end

      def initialize(url:, line: nil, column: nil, function_name: "")
        @url = url
        @line = line
        @column = column
        @function_name = function_name
      end

      # The location as `url:line:column`, leaving out what's unknown.
      #
      # @return [String]
      def to_s
        [url, line, column].compact.join(":")
      end
    end
  end
end
