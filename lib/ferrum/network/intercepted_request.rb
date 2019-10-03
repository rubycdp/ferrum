# frozen_string_literal: true

module Ferrum
  class Network
    class InterceptedRequest
      attr_accessor :interception_id, :frame_id, :resource_type

      def initialize(page, params)
        @page, @params = page, params
        @interception_id = params["interceptionId"]
        @frame_id = params["frameId"]
        @resource_type = params["resourceType"]
        @request = params["request"]
      end

      def navigation_request?
        @params["isNavigationRequest"]
      end

      def auth_challenge?(source)
        @params.dig("authChallenge", "source")&.downcase&.to_s == source.to_s
      end

      def match?(regexp)
        !!url.match(regexp)
      end

      def continue(**options)
        options = options.merge(interceptionId: interception_id)
        @page.command("Network.continueInterceptedRequest", **options)
      end

      def abort
        continue(errorReason: "BlockedByClient")
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
        %(#<#{self.class} @interception_id=#{@interception_id.inspect} @frame_id=#{@frame_id.inspect} @resource_type=#{@resource_type.inspect} @request=#{@request.inspect}>)
      end
    end
  end
end
