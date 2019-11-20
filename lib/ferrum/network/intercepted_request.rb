# frozen_string_literal: true

require "base64"

module Ferrum
  class Network
    class InterceptedRequest
      attr_accessor :request_id, :frame_id, :resource_type

      def initialize(page, params)
        @page, @params = page, params
        @request_id = params["requestId"]
        @frame_id = params["frameId"]
        @resource_type = params["resourceType"]
        @request = params["request"]
      end

      def navigation_request?
        @params["isNavigationRequest"]
      end

      def match?(regexp)
        !!url.match(regexp)
      end

      def respond(**options)
        has_body = options.has_key?(:body)
        headers = has_body ? { "content-length" => options.fetch(:body, "").length } : {}
        headers = headers.merge(options.fetch(:responseHeaders, {}))

        options = {responseCode: 200}.merge(options)
        options = options.merge({
          requestId: request_id,
          responseHeaders: header_array(headers),
        })
        options = options.merge(body: Base64.encode64(options.fetch(:body, "")).strip) if has_body

        @page.command("Fetch.fulfillRequest", **options)
      end

      def continue(**options)
        options = options.merge(requestId: request_id)
        @page.command("Fetch.continueRequest", **options)
      end

      def abort
        @page.command("Fetch.failRequest", requestId: request_id, errorReason: "BlockedByClient")
      end

      def url
        @request["url"]
      end

      def method
        @request["method"]
      end

      def headers
        @request["headers"]
      end

      def initial_priority
        @request["initialPriority"]
      end

      def referrer_policy
        @request["referrerPolicy"]
      end

      def inspect
        %(#<#{self.class} @request_id=#{@request_id.inspect} @frame_id=#{@frame_id.inspect} @resource_type=#{@resource_type.inspect} @request=#{@request.inspect}>)
      end

      private

      def header_array(values)
        values.map do |key, value|
          { name: String(key), value: String(value) }
        end
      end
    end
  end
end
