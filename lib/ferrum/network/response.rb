# frozen_string_literal: true

module Ferrum
  class Network
    class Response
      attr_reader :body_size

      def initialize(params)
        @params = params
        @response = params["response"] || @params["redirectResponse"]
      end

      def id
        @params["requestId"]
      end

      def url
        @response["url"]
      end

      def status
        @response["status"]
      end

      def status_text
        @response["statusText"]
      end

      def headers
        @response["headers"]
      end

      def headers_size
        @response["encodedDataLength"]
      end

      def content_type
        @content_type ||= @response.dig("headers", "contentType")&.sub(/;.*\z/, "")
      end

      # See https://crbug.com/883475
      # Sometimes we never get the Network.responseReceived event.
      # See https://crbug.com/764946
      # `Network.loadingFinished` encodedDataLength contains both body and
      # headers sizes received by wire.
      def body_size=(size)
        @body_size = size - headers_size
      end
    end
  end
end
