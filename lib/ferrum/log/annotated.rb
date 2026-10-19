# frozen_string_literal: true

require "ferrum/log/paint"

module Ferrum
  class Log
    #
    # Formats CDP messages one line each, the JSON whole after a header: the
    # direction, the elapsed time, the command id and method. Received
    # messages are indented under the commands sent. A response also
    # names the method of its command and how long the answer took. Picked
    # with `FERRUM_LOG_FORMAT=annotated`.
    #
    class Annotated
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
        line(paint("▶", :cyan), time(elapsed), "##{message[:id]}", paint(message[:method], :bold),
             json(message[:params]), session(message[:sessionId]))
      end

      # @param [Hash{String => Object}, nil] message
      #
      # @param [String] raw
      #
      # @param [Float] elapsed
      #
      # @param [Array(String, Float), nil] command
      #   The method of the command this message answers and how long the
      #   answer took, in seconds.
      #
      # @return [String]
      def received(message, raw, elapsed, command = nil)
        return line("   ", paint("◀", :magenta), time(elapsed), raw) unless message
        return event(message, elapsed) unless message.key?("id")

        method, duration = command
        error = message["error"]
        line("   ", paint("◀", error ? :red : :green), time(elapsed), "##{message['id']}", paint(method, :bold),
             duration && "#{(duration * 1000).round}ms", json(error || message["result"]),
             session(message["sessionId"]))
      end

      private

      def event(message, elapsed)
        line("   ", paint("◀", :magenta), time(elapsed), paint(message["method"], :bold), json(message["params"]),
             session(message["sessionId"]))
      end

      def line(*parts)
        parts.map(&:to_s).reject(&:empty?).join(" ")
      end

      def time(elapsed)
        paint(format("%.3f", elapsed), :dim)
      end

      def json(value)
        Log.dump(value) unless value.nil? || value == {}
      end

      def session(id)
        paint("@#{id[0, 8]}", :dim) if id
      end
    end
  end
end
