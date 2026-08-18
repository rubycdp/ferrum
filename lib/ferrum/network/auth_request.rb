# frozen_string_literal: true

module Ferrum
  class Network
    class AuthRequest
      attr_accessor :request_id, :frame_id, :resource_type

      def initialize(page, params)
        @page = page
        @params = params
        @request_id = params["requestId"]
        @frame_id = params["frameId"]
        @resource_type = params["resourceType"]
        @request = params["request"]
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
      # Whether the authentication challenge's source matches the given
      # type.
      #
      # @param [String, Symbol] source
      #   One of `:server` or `:proxy`.
      #
      # @return [Boolean]
      #
      def auth_challenge?(source)
        @params.dig("authChallenge", "source")&.downcase&.to_s == source.to_s
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
      # Responds to the authentication challenge, e.g. with credentials or by
      # canceling it.
      #
      # @param [Hash] options
      #
      # @option options [String] :response
      #   One of `"Default"`, `"CancelAuth"`, or `"ProvideCredentials"`.
      #
      # @option options [String] :username
      #
      # @option options [String] :password
      #
      def continue(**options)
        options = options.merge(requestId: request_id)
        @page.command("Fetch.continueWithAuth", **options)
      end

      #
      # Cancels the authentication challenge and the request.
      #
      def abort
        @page.command("Fetch.failRequest", requestId: request_id, errorReason: "BlockedByClient")
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
      # Inspects the auth request.
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
    end
  end
end
