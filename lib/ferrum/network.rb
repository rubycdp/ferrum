# frozen_string_literal: true

require "ferrum/network/exchange"
require "ferrum/network/intercepted_request"

module Ferrum
  class Network
    CLEAR_TYPE = %i[traffic cache].freeze
    AUTHORIZE_TYPE = %i[server proxy].freeze
    RESOURCE_TYPES = %w[Document Stylesheet Image Media Font Script TextTrack
                        XHR Fetch EventSource WebSocket Manifest
                        SignedExchange Ping CSPViolationReport Other].freeze

    attr_reader :traffic

    def initialize(page)
      @page = page
      @traffic = []
      @exchange = nil
    end

    def request
      @exchange&.request
    end

    def response
      @exchange&.response
    end

    def status
      response&.status
    end

    def clear(type)
      unless CLEAR_TYPE.include?(type)
        raise ArgumentError, ":type should be in #{CLEAR_TYPE}"
      end

      if type == :traffic
        @traffic.clear
      else
        @page.command("Network.clearBrowserCache")
      end

      true
    end

    def intercept(pattern: "*", resource_type: nil)
      pattern = { urlPattern: pattern }
      if resource_type && RESOURCE_TYPES.include?(resource_type.to_s)
        pattern[:resourceType] = resource_type
      end

      @page.command("Network.setRequestInterception", patterns: [pattern])
    end

    def authorize(user:, password:, type: :server)
      unless AUTHORIZE_TYPE.include?(type)
        raise ArgumentError, ":type should be in #{AUTHORIZE_TYPE}"
      end

      @authorized_ids ||= {}
      @authorized_ids[type] ||= []

      intercept

      @page.on(:request) do |request, index, total|
        if request.auth_challenge?(type)
          response = authorized_response(@authorized_ids[type],
                                         request.interception_id,
                                         user, password)

          @authorized_ids[type] << request.interception_id
          request.continue(authChallengeResponse: response)
        elsif index + 1 < total
          next # There are other callbacks that can handle this
        else
          request.continue
        end
      end
    end

    def subscribe
      @page.on("Network.requestWillBeSent") do |params|
        # On redirects Chrome doesn't change `requestId` and there's no
        # `Network.responseReceived` event for such request. If there's already
        # exchange object with this id then we got redirected and params has
        # `redirectResponse` key which contains the response.
        if exchange = first_by(params["requestId"])
          exchange.build_response(params)
        end

        exchange = Network::Exchange.new(@page, params)
        @exchange = exchange if exchange.navigation_request?(@page.main_frame.id)
        @traffic << exchange
      end

      @page.on("Network.responseReceived") do |params|
        if exchange = last_by(params["requestId"])
          exchange.build_response(params)
        end
      end

      @page.on("Network.loadingFinished") do |params|
        exchange = last_by(params["requestId"])
        if exchange && exchange.response
          exchange.response.body_size = params["encodedDataLength"]
        end
      end

      @page.on("Log.entryAdded") do |params|
        entry = params["entry"] || {}
        if entry["source"] == "network" &&
            entry["level"] == "error" &&
            exchange = last_by(entry["networkRequestId"])
          exchange.build_error(entry)
        end
      end
    end

    def authorized_response(ids, interception_id, username, password)
      if ids.include?(interception_id)
        { response: "CancelAuth" }
      elsif username && password
        { response: "ProvideCredentials",
          username: username,
          password: password }
      else
        { response: "CancelAuth" }
      end
    end

    def first_by(request_id)
      @traffic.find { |e| e.request.id == request_id }
    end

    def last_by(request_id)
      @traffic.select { |e| e.request.id == request_id }.last
    end
  end
end
