# frozen_string_literal: true

module Ferrum
  class Log
    #
    # Formats CDP messages as JSON alone, one message per line, for tools such
    # as `jq`. Commands, responses and events tell apart by their keys: `id`
    # and `method`, `id` and `result` or `error`, `method` alone. Never
    # colored. Picked with `FERRUM_LOG_FORMAT=json`.
    #
    class Json
      def initialize(**); end

      # @param [Hash{Symbol => Object}] message
      #
      # @return [String]
      def sent(message, _elapsed)
        Log.dump(message)
      end

      # @param [Hash{String => Object}, nil] message
      #
      # @param [String] raw
      #   Written as is when the message couldn't be parsed.
      #
      # @return [String]
      def received(message, raw, _elapsed, _command = nil)
        message ? Log.dump(message) : raw
      end
    end
  end
end
