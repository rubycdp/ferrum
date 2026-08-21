# frozen_string_literal: true

require "concurrent-ruby"
require "forwardable"
require "ferrum/client/subscriber"
require "ferrum/client/web_socket"
require "ferrum/utils/thread"

module Ferrum
  #
  # A thin wrapper around {Client} that scopes commands and events to a
  # single CDP session (a `sessionId` obtained via `Target.attachToTarget`).
  # Targets connect through one of these rather than the top-level {Client}
  # directly, so their commands/events don't leak into other sessions.
  # Method calls not defined here are forwarded to the underlying {Client}.
  #
  class SessionClient
    attr_reader :client, :session_id

    #
    # Builds the internal event key used to route an event to a specific
    # session, joining the CDP event name with a session id (or leaving it
    # session-less when `session_id` is `nil`).
    #
    # @param [String] event
    #   The CDP event name, e.g. `"Page.loadEventFired"`.
    #
    # @param [String, nil] session_id
    #   The target session id, or `nil` for the browser-wide session.
    #
    # @return [String]
    #
    def self.event_name(event, session_id)
      [event, session_id].compact.join("_")
    end

    def initialize(client, session_id)
      @client = client
      @session_id = session_id
    end

    #
    # Sends a CDP command scoped to this session.
    #
    # @param [String] method
    #   The CDP method name, e.g. `"Page.navigate"`.
    #
    # @param [Boolean] async
    #   Whether to send the command without waiting for a response.
    #
    # @param [Hash] params
    #   The command's parameters.
    #
    # @param [Numeric, nil] timeout
    #   How long to wait for this command's response, overriding
    #   {Browser::Options#protocol_timeout}. See {Client#send_message}.
    #
    # @return [Boolean, Hash]
    #   `true` when sent asynchronously, otherwise the command's result.
    #
    def command(method, async: false, timeout: nil, **params)
      message = build_message(method, params)
      @client.send_message(message, async: async, timeout: timeout)
    end

    #
    # Subscribes to a CDP event scoped to this session.
    #
    # @param [String] event
    #   The CDP event name.
    #
    # @return [Integer]
    #   The subscription id, used to unsubscribe via {#off}.
    #
    def on(event, &)
      @client.on(event_name(event), &)
    end

    #
    # Unsubscribes from a CDP event scoped to this session.
    #
    # @param [String] event
    #   The CDP event name.
    #
    # @param [Integer] id
    #   The subscription id returned by {#on}.
    #
    # @return [void]
    #
    def off(event, id)
      @client.off(event_name(event), id)
    end

    # Whether there's at least one callback registered for the event, scoped
    # to this session.
    #
    # @param [String] event
    #   The CDP event name.
    #
    # @return [Boolean]
    def subscribed?(event)
      @client.subscribed?(event_name(event))
    end

    # Supports {#method_missing} delegation by reporting the underlying
    # {Client}'s methods as responded to.
    #
    # @return [Boolean]
    def respond_to_missing?(name, include_private)
      @client.respond_to?(name, include_private)
    end

    #
    # Delegates any method not defined on `SessionClient` to the underlying
    # {Client}, e.g. `subscribed?`.
    #
    # @return [untyped]
    #
    def method_missing(name, ...)
      @client.send(name, ...)
    end

    #
    # Removes all event callbacks registered for this session from the
    # underlying client's subscriber.
    #
    # @return [void]
    #
    def close
      @client.subscriber.clear(session_id: session_id)
    end

    private

    def build_message(method, params)
      @client.build_message(method, params).merge(sessionId: session_id)
    end

    def event_name(event)
      self.class.event_name(event, session_id)
    end
  end

  #
  # The low-level CDP client. Owns the {WebSocket} connection to the browser,
  # assigns command ids, matches responses back to their pending commands and
  # dispatches incoming events to the {Subscriber}. {SessionClient} builds on
  # top of it to scope commands/events to a particular target's session.
  #
  class Client
    extend Forwardable

    delegate %i[protocol_timeout protocol_timeout=] => :options

    attr_reader :ws_url, :options, :subscriber

    def initialize(ws_url, options)
      @command_id = 0
      @command_id_mutex = Mutex.new
      @ws_url = ws_url
      @options = options
      @pendings = Concurrent::Hash.new
      @ws = WebSocket.new(ws_url, options.ws_max_receive_size, options.logger)
      @subscriber = Subscriber.new

      start
    end

    #
    # Sends a CDP command to the browser-wide session.
    #
    # @param [String] method
    #   The CDP method name, e.g. `"Target.createTarget"`.
    #
    # @param [Boolean] async
    #   Whether to send the command without waiting for a response.
    #
    # @param [Hash] params
    #   The command's parameters.
    #
    # @param [Numeric, nil] timeout
    #   How long to wait for this command's response, overriding
    #   {Browser::Options#protocol_timeout}. See {#send_message}.
    #
    # @return [Boolean, Hash]
    #   `true` when sent asynchronously, otherwise the command's result.
    #
    def command(method, async: false, timeout: nil, **params)
      message = build_message(method, params)
      send_message(message, async: async, timeout: timeout)
    end

    #
    # Sends a raw CDP message over the websocket. Synchronous calls block
    # until a matching response arrives, or `timeout` elapses, defaulting to
    # `protocol_timeout` (delegated to {Browser::Options#protocol_timeout}).
    # That default is the transport-level budget for internal CDP bookkeeping
    # (e.g. `Target.createTarget`). {Page#command} overrides
    # this back to `timeout`, or a caller-supplied budget (e.g. `#pdf`/
    # `#screenshot`'s own `timeout:` argument), for the user-facing commands
    # it issues -- some of which (e.g. `Page.navigate`, `Page.printToPDF`)
    # rely on their own response latency to detect a stuck operation.
    #
    # @param [Hash] message
    #   The message to send, must include an `:id` key.
    #
    # @param [Boolean] async
    #   Whether to return immediately instead of waiting for a response.
    #
    # @param [Numeric, nil] timeout
    #   How long to wait for the response. Defaults to `protocol_timeout`.
    #
    # @return [Boolean, Hash]
    #   `true` when sent asynchronously, otherwise the parsed `"result"`
    #   from the response.
    #
    def send_message(message, async:, timeout: nil)
      if async
        @ws.send_message(message)
        true
      else
        pending = Concurrent::IVar.new
        @pendings[message[:id]] = pending
        @ws.send_message(message)
        data = pending.value!(timeout || protocol_timeout)
        @pendings.delete(message[:id])

        raise DeadBrowserError if data.nil? && @ws.messages.closed?
        raise TimeoutError unless data

        error, response = data.values_at("error", "result")
        raise_browser_error(error) if error
        response
      end
    end

    #
    # Subscribes to a CDP event.
    #
    # @param [String] event
    #   The CDP event name.
    #
    # @return [Integer]
    #   The subscription id, used to unsubscribe via {#off}.
    #
    def on(event, &)
      @subscriber.on(event, &)
    end

    #
    # Unsubscribes from a CDP event.
    #
    # @param [String] event
    #   The CDP event name.
    #
    # @param [Integer] id
    #   The subscription id returned by {#on}.
    #
    # @return [void]
    #
    def off(event, id)
      @subscriber.off(event, id)
    end

    # Whether there's at least one callback registered for the event.
    #
    # @param [String] event
    #   The CDP event name.
    #
    # @return [Boolean]
    def subscribed?(event)
      @subscriber.subscribed?(event)
    end

    #
    # Builds a client scoped to a given CDP session, e.g. a browsing
    # context created via `Target.attachToTarget`.
    #
    # @param [String] session_id
    #   The CDP session id to scope commands and events to.
    #
    # @return [SessionClient]
    #
    def session(session_id)
      SessionClient.new(self, session_id)
    end

    #
    # Closes the underlying websocket, drops pending commands and stops
    # the message-processing thread and subscriber.
    #
    # @return [void]
    #
    def close
      @ws.close
      # Give a thread some time to handle a tail of messages
      @pendings.clear
      @thread.kill unless @thread.join(1)
      @subscriber.close
    end

    #
    # Custom inspection that exposes internal state useful for debugging.
    #
    # @return [String]
    #
    def inspect
      "#<#{self.class} " \
        "@command_id=#{@command_id.inspect} " \
        "@pendings=#{@pendings.inspect} " \
        "@ws=#{@ws.inspect}>"
    end

    #
    # Builds a CDP message hash with a fresh, thread-safe command id.
    #
    # @param [String] method
    #   The CDP method name.
    #
    # @param [Hash] params
    #   The command's parameters.
    #
    # @return [Hash]
    #
    def build_message(method, params)
      { method: method, params: params }.merge(id: next_command_id)
    end

    private

    def start
      @thread = Utils::Thread.spawn do
        loop do
          message = @ws.messages.pop
          break unless message

          if message.key?("method")
            @subscriber << message
          else
            @pendings[message["id"]]&.set(message)
          end
        end
      end
    end

    # Locked so two concurrent commands never share an id and read each
    # other's responses from @pendings.
    def next_command_id
      @command_id_mutex.synchronize { @command_id += 1 }
    end

    def raise_browser_error(error)
      case error["message"]
      # Node has disappeared while we were trying to get it
      when "No node with given id found",
           "Could not find node with given id",
           "Inspected target navigated or closed"
        raise NodeNotFoundError, error
      # Context is lost, page is reloading
      when "Cannot find context with specified id"
        raise NoExecutionContextError, error
      when "No target with given id found"
        raise NoSuchPageError
      when /Could not compute content quads/
        raise CoordinatesNotFoundError
      else
        raise BrowserError, error
      end
    end
  end
end
