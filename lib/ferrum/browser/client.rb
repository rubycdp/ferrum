# frozen_string_literal: true

require "forwardable"
require "ferrum/browser/subscriber"
require "ferrum/browser/web_socket"

module Ferrum
  class Browser
    class Client
      extend Forwardable
      delegate %i[timeout timeout=] => :options

      attr_reader :options

      def initialize(ws_url, options)
        @command_id = 0
        @options = options
        @pendings = Concurrent::Hash.new
        @ws = WebSocket.new(ws_url, options.ws_max_receive_size, options.logger)
        @subscriber = Subscriber.new

        start
      end

      def command(method, params = {})
        pending = Concurrent::IVar.new
        message = build_message(method, params)
        @pendings[message[:id]] = pending
        @ws.send_message(message)
        data = pending.value!(timeout)
        @pendings.delete(message[:id])

        raise DeadBrowserError if data.nil? && @ws.messages.closed?
        raise TimeoutError unless data

        error, response = data.values_at("error", "result")
        raise_browser_error(error) if error
        response
      end

      def on(event, &block)
        @subscriber.on(event, &block)
      end

      def subscribed?(event)
        @subscriber.subscribed?(event)
      end

      def close
        @ws.close
        # Give a thread some time to handle a tail of messages
        @pendings.clear
        @thread.kill unless @thread.join(1)
        @subscriber.close
      end

      def inspect
        "#<#{self.class} " \
          "@command_id=#{@command_id.inspect} " \
          "@pendings=#{@pendings.inspect} " \
          "@ws=#{@ws.inspect}>"
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

      def build_message(method, params)
        { method: method, params: params }.merge(id: next_command_id)
      end

      def next_command_id
        @command_id += 1
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
end
