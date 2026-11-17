# frozen_string_literal: true

require "forwardable"
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
    # @param [Numeric, Deadline] timeout
    #   How long to wait for this command's response. See {Client#send_message}.
    #
    # @param [Hash] params
    #   The command's parameters.
    #
    # @return [Hash]
    #   The command's result.
    #
    # @raise [TimeoutError]
    #
    def command(method, timeout:, **params)
      message = build_message(method, params)
      @client.send_message(message, timeout: timeout)
    end

    #
    # Sends a CDP command scoped to this session without waiting for a response.
    #
    # @param [String] method
    #   The CDP method name, e.g. `"Runtime.runIfWaitingForDebugger"`.
    #
    # @param [Hash] params
    #   The command's parameters.
    #
    # @return [true]
    #
    def notify(method, **params)
      @client.send_notification(build_message(method, params))
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
    # underlying client's dispatcher.
    #
    # @return [void]
    #
    def close
      @client.dispatcher.clear { |k| k.match?(session_id) }
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
  # dispatches incoming events to the {Concurrency::Dispatcher}. {SessionClient} builds on
  # top of it to scope commands/events to a particular target's session.
  #
  class Client
    extend Forwardable

    PROTOCOL_TIMEOUT = 5
    INTERRUPTIONS = %w[Fetch.requestPaused Fetch.authRequired].freeze

    delegate %i[timeout] => :options

    attr_reader :ws_url, :options, :dispatcher

    def initialize(ws_url, options)
      @command_id = 0
      @command_id_mutex = Mutex.new
      @ws_url = ws_url
      @options = options
      @responses = Concurrency::AwaitableMap.new
      @ws = WebSocket.new(ws_url, options.ws_max_receive_size, options.log)
      @dispatcher = Concurrency::Dispatcher.new

      start
    end

    #
    # Sends a CDP command to the browser-wide session.
    #
    # @param [String] method
    #   The CDP method name, e.g. `"Target.createTarget"`.
    #
    # @param [Numeric, Deadline] timeout
    #   How long to wait for this command's response. See {#send_message}.
    #
    # @param [Hash] params
    #   The command's parameters.
    #
    # @return [Hash]
    #   The command's result.
    #
    def command(method, timeout:, **params)
      message = build_message(method, params)
      send_message(message, timeout: timeout)
    end

    #
    # Sends a CDP command to the browser-wide session without waiting for a response.
    #
    # @param [String] method
    #   The CDP method name, e.g. `"Target.closeTarget"`.
    #
    # @param [Hash] params
    #   The command's parameters.
    #
    # @return [true]
    #
    def notify(method, **params)
      send_notification(build_message(method, params))
    end

    #
    # Sends a raw CDP message over the websocket and blocks until a matching
    # response arrives or `timeout` elapses. The caller says how long that is,
    # so the budget it runs under is visible. Pass the {Deadline} of the
    # surrounding operation to share its budget; inside {Deadline.within} the
    # budget is also bound by the one that block sets.
    #
    # @param [Hash] message
    #   The message to send, must include an `:id` key.
    #
    # @param [Numeric, Deadline] timeout
    #   How long to wait for the response, counting the time the message waits
    #   to be sent.
    #
    # @return [Hash]
    #   The parsed `"result"` from the response.
    #
    def send_message(message, timeout:)
      deadline = Deadline.wrap(timeout)

      raise dead_browser_error if @ws.messages.closed?

      @responses.expect(message[:id])
      begin
        @ws.send_message(message, deadline)
        data = @responses.await(message[:id], deadline)
      ensure
        @responses.delete(message[:id])
      end

      raise dead_browser_error if data.nil? && @ws.messages.closed?
      raise TimeoutError.new(message[:method], session_id: message[:sessionId]) unless data

      error, response = data.values_at("error", "result")
      raise_browser_error(error) if error
      response
    end

    #
    # Sends a raw CDP message over the websocket without waiting for a
    # response, which is dropped when it arrives. Nothing bounds it: a browser
    # that stops reading is detected by the write watchdog.
    #
    # @param [Hash] message
    #   The message to send, must include an `:id` key.
    #
    # @return [true]
    #
    def send_notification(message)
      @ws.send_message(message)
      true
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
      @dispatcher.on(event, &)
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
      @dispatcher.off(event, id)
    end

    # Whether there's at least one callback registered for the event.
    #
    # @param [String] event
    #   The CDP event name.
    #
    # @return [Boolean]
    def subscribed?(event)
      @dispatcher.subscribed?(event)
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
    # the message-processing thread and dispatcher.
    #
    # @return [void]
    #
    def close
      @ws.close
      # Give a thread some time to handle a tail of messages
      @responses.close
      @thread.kill unless @thread.join(1)
      @dispatcher.close
      @ws.force_close
    end

    #
    # Custom inspection that exposes internal state useful for debugging.
    #
    # @return [String]
    #
    def inspect
      "#<#{self.class} " \
        "@command_id=#{@command_id.inspect} " \
        "@responses=#{@responses.inspect} " \
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
            dispatch(message)
          else
            @responses.fulfill(message["id"], message)
          end
        end
      rescue StandardError => e
        # Nothing delivers responses once this thread is gone, so the connection
        # is done for. Close it rather than leave every command hanging.
        warn("Ferrum: dispatch stopped, #{e.class}: #{e.message}\n  #{e.backtrace&.first}")
        @ws.messages.close
      ensure
        release_commands
      end
    end

    # Request interception events take the priority lane so they aren't delayed behind the others.
    def dispatch(message)
      method, session_id, params = message.values_at("method", "sessionId", "params")
      lane = INTERRUPTIONS.include?(method) ? :priority : :regular
      @dispatcher.publish(SessionClient.event_name(method, session_id), params, lane: lane)
    end

    # Nothing is going to answer the commands still in flight once the socket
    # is gone, release them instead of making each wait out its timeout.
    def release_commands
      @responses.close
    end

    def dead_browser_error
      @ws.close_reason ? DeadBrowserError.new(@ws.close_reason) : DeadBrowserError.new
    end

    # Locked so two concurrent commands never share an id and read each
    # other's responses from @responses.
    def next_command_id
      @command_id_mutex.synchronize { @command_id += 1 }
    end

    def raise_browser_error(error)
      case error["message"]
      # Node has disappeared while we were trying to get it
      when "No node with given id found",
           "Could not find node with given id",
           "Inspected target navigated or closed",
           "Argument should belong to the same JavaScript world as target object"
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
