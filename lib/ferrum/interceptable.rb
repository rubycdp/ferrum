# frozen_string_literal: true

module Ferrum
  # Shared by {Page} and {Worker}: subscribes to the CDP events behind the
  # `:request` (Fetch-domain request interception), `:response` (a request's
  # response has fully loaded), `:auth` (proxy/basic auth challenges) and
  # `:console` (a new console message) pseudo-events, on top of the
  # includer's own `client`, `network` and `console`. Anything else is passed
  # straight through to `client`.
  module Interceptable
    # Subscribes to a CDP event, or to `:request`/`:response`/`:auth`/`:console`.
    #
    # @param [Symbol, String] name
    #
    # @yieldparam [Network::InterceptedRequest, Network::Exchange, Network::AuthRequest, Console::Message, Hash] arg
    #   For `:request`, the intercepted {Network::InterceptedRequest}. For
    #   `:response`, the finished {Network::Exchange}. For `:auth`, the
    #   {Network::AuthRequest} challenge. For `:console`, the new
    #   {Console::Message}. For any other (raw CDP) event name, the event's
    #   params `Hash`.
    #
    # @yieldparam [Integer] index
    #   This callback's position among all callbacks currently registered for
    #   the event. Not passed for `:console`.
    #
    # @yieldparam [Integer] total
    #   Total number of callbacks currently registered for the event. Not
    #   passed for `:console`.
    #
    # @return [Integer]
    #   The subscription id, used to unsubscribe via {#off}.
    #
    # @example
    #   page.on(:console) { |message| warn(message) if message.error? }
    def on(name, &block)
      case name
      when :console
        console.on(&block)
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
      when :console
        console.off(id)
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
