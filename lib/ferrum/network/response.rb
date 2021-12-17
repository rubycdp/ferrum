# frozen_string_literal: true

module Ferrum
  class Network
    class Response
      attr_reader :body_size, :params

      def initialize(page, params)
        @page = page
        @params = params
        @response = params["response"] || params["redirectResponse"]
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

      def type
        @params["type"]
      end

      def content_type
        @content_type ||= headers.find { |k, _| k.downcase == "content-type" }&.last&.sub(/;.*\z/, "")
      end

      # See https://crbug.com/883475
      # Sometimes we never get the Network.responseReceived event.
      # See https://crbug.com/764946
      # `Network.loadingFinished` encodedDataLength contains both body and
      # headers sizes received by wire.
      def body_size=(size)
        @body_size = size - headers_size
      end

      def body
        @body ||= begin
          body, encoded = @page
                          .command("Network.getResponseBody", requestId: id)
                          .values_at("body", "base64Encoded")
          encoded ? Base64.decode64(body) : body
        end
      end

      def main?
        @page.network.response == self
      end

      def ==(other)
        id == other.id
      end

      def inspect
        %(#<#{self.class} @params=#{@params.inspect} @response=#{@response.inspect}>)
      end
    end
  end
end
