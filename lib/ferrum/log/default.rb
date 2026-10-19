# frozen_string_literal: true

require "ferrum/log/paint"

module Ferrum
  class Log
    #
    # Formats CDP messages as Ferrum always has: the direction, the elapsed
    # time and the message as JSON. On a terminal the arrow is colored by
    # kind, the time dimmed and the method bold.
    #
    class Default
      include Paint

      def initialize(color: false)
        @color = color
      end

      # @param [Hash{Symbol => Object}] message
      #
      # @param [Float] elapsed
      #
      # @return [String]
      def sent(message, elapsed)
        "\n\n#{paint('▶', :cyan)} #{paint(elapsed, :dim)} #{payload(message, message[:method])}"
      end

      # @param [Hash{String => Object}, nil] message
      #
      # @param [String] raw
      #
      # @param [Float] elapsed
      #
      # @return [String]
      def received(message, raw, elapsed, _command = nil)
        arrow = if message.nil? || !message.key?("id") then :magenta
                elsif message.key?("error") then :red
                else :green
                end
        body = message ? payload(message, message["method"]) : raw

        "    #{paint('◀', arrow)} #{paint(elapsed, :dim)} #{body}\n"
      end

      private

      def payload(message, method)
        json = Log.dump(message)
        return json unless method && color?

        json.sub(%("method":"#{method}"), %("method":"#{paint(method, :bold)}"))
      end
    end
  end
end
