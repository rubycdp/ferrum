# frozen_string_literal: true

module Ferrum::Network
  class InterceptedRequest
    attr_accessor :interception_id, :frame_id, :resource_type,
                  :is_navigation_request

    def initialize(page, params)
      @page, @params = page, params
      @interception_id = params["interceptionId"]
      @frame_id = params["frameId"]
      @resource_type = params["resourceType"]
      @is_navigation_request = params["isNavigationRequest"]
      @request = params.dig("request")
    end

    def auth_challenge?(source)
      @params.dig("authChallenge", "source")&.downcase&.to_s == source.to_s
    end

    def match?(regexp)
      !!url.match(regexp)
    end

    def abort
      @page.abort_request(interception_id)
    end

    def continue(**options)
      @page.continue_request(interception_id, **options)
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
  end
end
