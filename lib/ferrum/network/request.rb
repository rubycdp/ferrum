# frozen_string_literal: true

require "time"

module Ferrum
  class Network
    class Request
      def initialize(params)
        @params = params
        @request = @params["request"]
      end

      def id
        @params["requestId"]
      end

      def type
        @params["type"]
      end

      def type?(value)
        type.downcase == value.to_s.downcase
      end

      def frame_id
        @params["frameId"]
      end

      def url
        @request["url"]
      end

      def url_fragment
        @request["urlFragment"]
      end

      def method
        @request["method"]
      end

      def headers
        @request["headers"]
      end

      def time
        @time ||= Time.strptime(@params["wallTime"].to_s, "%s")
      end

      def post_data
        @request["postData"]
      end
      alias body post_data
    end
  end
end
