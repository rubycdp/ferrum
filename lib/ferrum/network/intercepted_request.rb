# frozen_string_literal: true

require "ferrum/network/request_params"
require "base64"

module Ferrum
  class Network
    class InterceptedRequest
      include RequestParams

      attr_accessor :request_id, :frame_id, :resource_type, :network_id, :status

      def initialize(client, params)
        @status = nil
        @client = client
        @params = params
        @request_id = params["requestId"]
        @frame_id = params["frameId"]
        @resource_type = params["resourceType"]
        @request = params["request"]
        @network_id = params["networkId"]
      end

      #
      # Whether the request's current status matches the given value.
      #
      # @param [String, Symbol] value
      #   One of `:responded`, `:continued`, `:aborted`.
      #
      # @return [Boolean]
      #
      def status?(value)
        @status == value.to_sym
      end

      #
      # Whether this request is for the navigation of a frame, as opposed
      # to a subresource (script, image, XHR, etc).
      #
      # @return [Boolean]
      #
      def navigation_request?
        @params["isNavigationRequest"]
      end

      #
      # Whether the request's URL matches the given pattern.
      #
      # @param [String, Regexp] pattern
      #
      # @return [Boolean]
      #
      def match?(pattern)
        case url
        when pattern
          true
        else
          false
        end
      end

      #
      # Fulfills the intercepted request with a fake response instead of
      # letting it reach the network.
      #
      # @param [Hash] options
      #
      # @option options [Integer] :responseCode
      #   HTTP status code to respond with, `200` by default.
      #
      # @option options [String] :body
      #   Response body.
      #
      # @option options [Hash] :responseHeaders
      #   Response headers.
      #
      # @example
      #   request.respond(body: "Lorem ipsum")
      #
      def respond(**options)
        has_body = options.key?(:body)
        headers = has_body ? { "content-length" => options.fetch(:body, "").length } : {}
        headers = headers.merge(options.fetch(:responseHeaders, {}))

        options = { responseCode: 200 }.merge(options)
        options = options.merge(requestId: request_id, responseHeaders: header_array(headers))
        options = options.merge(body: Base64.strict_encode64(options.fetch(:body, ""))) if has_body

        @status = :responded
        @client.command("Fetch.fulfillRequest", async: true, **options)
      end

      #
      # Continues the intercepted request, letting it reach the network as
      # is, or with the given overrides.
      #
      # @param [Hash] options
      #
      # @option options [String] :url
      #   Overrides the request's URL.
      #
      # @option options [String] :method
      #   Overrides the request's method.
      #
      # @option options [String] :postData
      #   Overrides the request's post data.
      #
      # @option options [Hash] :headers
      #   Overrides the request's headers.
      #
      # @example
      #   request.continue
      #
      def continue(**options)
        options = options.merge(requestId: request_id)
        @status = :continued
        @client.command("Fetch.continueRequest", async: true, **options)
      end

      #
      # Aborts the intercepted request.
      #
      # @example
      #   request.abort
      #
      def abort
        @status = :aborted
        @client.command("Fetch.failRequest", async: true, requestId: request_id, errorReason: "BlockedByClient")
      end

      #
      # The request's initial priority, one of `"VeryLow"`, `"Low"`,
      # `"Medium"`, `"High"`, or `"VeryHigh"`.
      #
      # @return [String]
      #
      def initial_priority
        @request["initialPriority"]
      end

      #
      # The request's referrer policy.
      #
      # @return [String]
      #
      def referrer_policy
        @request["referrerPolicy"]
      end

      #
      # Inspects the intercepted request.
      #
      # @return [String]
      #
      def inspect
        "#<#{self.class} " \
          "@request_id=#{@request_id.inspect} " \
          "@frame_id=#{@frame_id.inspect} " \
          "@resource_type=#{@resource_type.inspect} " \
          "@request=#{@request.inspect}>"
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
