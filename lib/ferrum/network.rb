# frozen_string_literal: true

require "ferrum/network/exchange"
require "ferrum/network/intercepted_request"
require "ferrum/network/auth_request"
require "ferrum/network/error"
require "ferrum/network/request"
require "ferrum/network/response"

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

    def wait_for_idle(connections: 0, duration: 0.05, timeout: @page.browser.timeout)
      start = Ferrum.monotonic_time

      until idle?(connections)
        raise TimeoutError if Ferrum.timeout?(start, timeout)
        sleep(duration)
      end
    end

    def idle?(connections = 0)
      pending_connections <= connections
    end

    def total_connections
      @traffic.size
    end

    def finished_connections
      @traffic.count(&:finished?)
    end

    def pending_connections
      total_connections - finished_connections
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

      @page.command("Fetch.enable", handleAuthRequests: true, patterns: [pattern])
    end

    def authorize(user:, password:, type: :server, &block)
      unless AUTHORIZE_TYPE.include?(type)
        raise ArgumentError, ":type should be in #{AUTHORIZE_TYPE}"
      end

      @authorized_ids ||= {}
      @authorized_ids[type] ||= []

      intercept

      if block_given?
        @page.on(:request, &block)
      else
        warn "[DEPRECATION] `authorize` without `&block` is deprecated. Please see details https://github.com/rubycdp/ferrum#authorizeoptions"

        @page.on(:request) do |request|
          request.continue
        end
      end

      @page.on(:auth) do |request, index, total|
        if request.auth_challenge?(type)
          response = authorized_response(@authorized_ids[type],
                                         request.request_id,
                                         user, password)

          @authorized_ids[type] << request.request_id
          request.continue(authChallengeResponse: response)
        elsif index + 1 < total
          next # There are other callbacks that can handle this
        else
          request.abort
        end
      end
    end

    def subscribe
      @page.on("Network.requestWillBeSent") do |params|
        request = Network::Request.new(params)

        # We can build exchange in two places, here on the event or when request
        # is interrupted. So we have to be careful when to create new one. We
        # create new exchange only if there's no with such id or there's but
        # it's filled with request which means this one is new but has response
        # for a redirect. So we assign response from the params to previous
        # exchange and build new exchange to assign this request to it.
        exchange = select(request.id).last
        exchange = build_exchange(request.id) unless exchange&.blank?

        # On redirects Chrome doesn't change `requestId` and there's no
        # `Network.responseReceived` event for such request. If there's already
        # exchange object with this id then we got redirected and params has
        # `redirectResponse` key which contains the response.
        if params["redirectResponse"]
          previous_exchange = select(request.id)[-2]
          response = Network::Response.new(@page, params)
          previous_exchange.response = response
        end

        exchange.request = request

        if exchange.navigation_request?(@page.main_frame.id)
          @exchange = exchange
        end
      end

      @page.on("Network.responseReceived") do |params|
        if exchange = select(params["requestId"]).last
          response = Network::Response.new(@page, params)
          exchange.response = response
        end
      end

      @page.on("Network.loadingFinished") do |params|
        exchange = select(params["requestId"]).last
        if exchange && exchange.response
          exchange.response.body_size = params["encodedDataLength"]
        end
      end

      @page.on("Network.loadingFailed") do |params|
        exchange = select(params["requestId"]).last
        exchange.error ||= Network::Error.new

        exchange.error.id = params["requestId"]
        exchange.error.type = params["type"]
        exchange.error.error_text = params["errorText"]
        exchange.error.monotonic_time = params["timestamp"]
        exchange.error.canceled = params["canceled"]
      end

      @page.on("Log.entryAdded") do |params|
        entry = params["entry"] || {}
        if entry["source"] == "network" && entry["level"] == "error"
          exchange = select(entry["networkRequestId"]).last
          exchange.error ||= Network::Error.new

          exchange.error.id = entry["networkRequestId"]
          exchange.error.url = entry["url"]
          exchange.error.description = entry["text"]
          exchange.error.timestamp = entry["timestamp"]
        end
      end
    end

    def authorized_response(ids, request_id, username, password)
      if ids.include?(request_id)
        { response: "CancelAuth" }
      elsif username && password
        { response: "ProvideCredentials",
          username: username,
          password: password }
      else
        { response: "CancelAuth" }
      end
    end

    def select(request_id)
      @traffic.select { |e| e.id == request_id }
    end

    def build_exchange(id)
      Network::Exchange.new(@page, id).tap { |e| @traffic << e }
    end
  end
end
