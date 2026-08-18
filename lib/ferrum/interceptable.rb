# frozen_string_literal: true

module Ferrum
  # Shared by {Page} and {Worker}: subscribes to the CDP events behind the
  # `:request` (Fetch-domain request interception) and `:auth` (proxy/basic
  # auth challenges) pseudo-events, on top of the includer's own `client`
  # and `network`. Anything else is passed straight through to `client`.
  module Interceptable
    # Subscribes to a CDP event, or to `:request`/`:auth`.
    #
    # @param [Symbol, String] name
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
