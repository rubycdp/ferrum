# frozen_string_literal: true

require "ferrum/interceptable/chain"

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
    # `:request` and `:auth` callbacks form a chain: they run in the order they
    # were added, and the rest are skipped as soon as one of them handles the
    # object (`continue`, `respond`, `abort`). An object nobody handled is
    # continued, an auth challenge gets Chrome's default response.
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
    # @return [Integer]
    #   The subscription id, used to unsubscribe via {#off}.
    #
    # @example
    #   page.on(:console) { |message| warn(message) if message.error? }
    #
    # @example
    #   page.on(:request) { |r| r.abort if r.match?(/ads/) }
    #   page.on(:request) { |r| r.respond(body: "stub") if r.match?(/api/) }
    def on(name, &block)
      case name
      when :console
        console.on(&block)
      when :request, :auth
        chain(name).add(&block)
      when :response
        client.on("Network.loadingFinished") do |params|
          exchange = network.select(params["requestId"]).last
          block.call(exchange) if exchange
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
      when :request, :auth
        chain(name).remove(id)
      when :response
        client.off("Network.loadingFinished", id)
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

    private

    def chain(name)
      @chains ||= Concurrent::Hash.new
      @chains[name] ||= build_chain(name)
    end

    def build_chain(name)
      case name
      when :request
        Chain.new(client, "Fetch.requestPaused",
                  build: lambda do |params|
                    request = Network::InterceptedRequest.new(client, params)
                    exchange = network.find_or_build_exchange(request.network_id)
                    exchange.intercepted_request = request
                    request
                  end,
                  default: lambda(&:continue))
      when :auth
        Chain.new(client, "Fetch.authRequired",
                  build: ->(params) { Network::AuthRequest.new(self, params) },
                  default: ->(request) { request.continue(authChallengeResponse: { response: "Default" }) })
      end
    end
  end
end
