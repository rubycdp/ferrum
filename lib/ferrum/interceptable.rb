# frozen_string_literal: true

module Ferrum
  # Shared by {Page} and {Worker}: subscribes to the CDP events behind the
  # `:request` (Fetch-domain request interception), `:response` (a request's
  # response has fully loaded) and `:auth` (proxy/basic auth challenges)
  # pseudo-events, on top of the includer's own `client` and `network`.
  # Anything else is passed straight through to `client`.
  module Interceptable
    # Subscribes to a CDP event, or to `:request`/`:response`/`:auth`.
    #
    # @param [Symbol, String] name
    #
    # @yieldparam [Network::InterceptedRequest, Network::Exchange, Network::AuthRequest, Hash] arg
    #   For `:request`, the intercepted {Network::InterceptedRequest}. For
    #   `:response`, the finished {Network::Exchange}. For `:auth`, the
    #   {Network::AuthRequest} challenge. For any other (raw CDP) event name,
    #   the event's params `Hash`.
    #
    # @yieldparam [Integer] index
    #   This callback's position among all callbacks currently registered for
    #   the event.
    #
    # @yieldparam [Integer] total
    #   Total number of callbacks currently registered for the event.
    #
    # @return [Integer]
    #   The subscription id, used to unsubscribe via {#off}.
    def on(name, &block)
      case name
      when :request
        client.on("Fetch.requestPaused") do |params, index, total|
          request = Network::InterceptedRequest.new(client, params)
          exchange = network.find_or_build_exchange(request.network_id)
          exchange.intercepted_request = request
          block.call(request, index, total)
        end
      when :response
        client.on("Network.loadingFinished") do |params, index, total|
          exchange = network.select(params["requestId"]).last
          block.call(exchange, index, total) if exchange
        end
      when :auth
        client.on("Fetch.authRequired") do |params, index, total|
          request = Network::AuthRequest.new(self, params)
          block.call(request, index, total)
        end
      else
        client.on(name, &block)
      end
    end

    # Unsubscribes a listener previously registered via {#on}.
    #
    # @param [Symbol, String] name
    #
    # @param [Integer] id
    #   The subscription id returned by {#on}.
    #
    # @return [void]
    def off(name, id)
      case name
      when :request
        client.off("Fetch.requestPaused", id)
      when :response
        client.off("Network.loadingFinished", id)
      when :auth
        client.off("Fetch.authRequired", id)
      else
        client.off(name, id)
      end
    end

    # Whether there's at least one callback registered for the event.
    #
    # @param [String] event
    #
    # @return [Boolean]
    def subscribed?(event)
      client.subscribed?(event)
    end
  end
end
