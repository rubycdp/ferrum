# frozen_string_literal: true

module Ferrum
  class Network
    class Error
      def initialize(data)
        @data = data
      end

      def id
        @data["networkRequestId"]
      end

      def url
        @data["url"]
      end

      def description
        @data["text"]
      end

      def time
        @time ||= Time.strptime(@data["timestamp"].to_s, "%s")
      end
    end
  end
end
