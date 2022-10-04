# frozen_string_literal: true

require "time"

module Ferrum
  class Network
    #
    # Represents a [Network.Request](https://chromedevtools.github.io/devtools-protocol/1-3/Network/#type-Request)
    # object.
    #
    class Request
      #
      # Initializes the request object.
      #
      # @param [Hash{String => Object}] params
      #   The parsed JSON attributes.
      #
      def initialize(params)
        @params = params
        @request = @params["request"]
      end

      #
      # The request ID.
      #
      # @return [String]
      #
      def id
        @params["requestId"]
      end

      #
      # The request resouce type.
      #
      # @return [String]
      #
      def type
        @params["type"]
      end

      #
      # Determines if the request is of the given type.
      #
      # @param [String, Symbol] value
      #   The type value to compare against.
      #
      # @return [Boolean]
      #
      def type?(value)
        type.downcase == value.to_s.downcase
      end

      #
      # The frame ID of the request.
      #
      # @return [String]
      #
      def frame_id
        @params["frameId"]
      end

      #
      # The URL for the request.
      #
      # @return [String]
      #
      def url
        @request["url"]
      end

      #
      # The URL fragment for the request.
      #
      # @return [String, nil]
      #
      def url_fragment
        @request["urlFragment"]
      end

      #
      # The request method.
      #
      # @return [String]
      #
      def method
        @request["method"]
      end

      #
      # The request headers.
      #
      # @return [Hash{String => String}]
      #
      def headers
        @request["headers"]
      end

      #
      # The request timestamp.
      #
      # @return [Time]
      #
      def time
        @time ||= Time.strptime(@params["wallTime"].to_s, "%s")
      end

      #
      # The optional HTTP `POST` form data.
      #
      # @return [String, nil]
      #   The HTTP `POST` form data.
      #
      def post_data
        @request["postData"]
      end
      alias body post_data
    end
  end
end
