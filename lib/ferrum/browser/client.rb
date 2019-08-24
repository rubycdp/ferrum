# frozen_string_literal: true

require "timeout"
require "ferrum/browser/web_socket"

module Ferrum
  class Browser
    class Client
      class IdError < RuntimeError; end

      def initialize(browser, ws_url, start_id = 0, allow_slowmo = true)
        @command_id = start_id
        @on = Hash.new { |h, k| h[k] = [] }
        @browser, @allow_slowmo = browser, allow_slowmo
        @commands = Queue.new
        @ws = WebSocket.new(ws_url, @browser.logger)

        @thread = Thread.new do
          while message = @ws.messages.pop
            method, params = message.values_at("method", "params")
            if method
              @on[method].each { |b| b.call(params) }
            else
              @commands.push(message)
            end
          end

          @commands.close
        end
      end

      def command(method, params = {})
        message = build_message(method, params)
        sleep(@browser.slowmo) if !@browser.slowmo.nil? && @allow_slowmo
        @ws.send_message(message)
        message[:id]
      end

      def wait(id:)
        message = Timeout.timeout(@browser.timeout, TimeoutError) { @commands.pop }
        raise DeadBrowser unless message
        raise IdError if message["id"] != id
        error, response = message.values_at("error", "result")
        raise BrowserError.new(error) if error
        response
      rescue IdError
        retry
      end

      def on(event, &block)
        @on[event] << block
        true
      end

      def close
        @ws.close
        # Give a thread some time to handle a tail of messages
        Timeout.timeout(1) { @thread.join }
      rescue Timeout::Error
        @thread.kill
      end

      private

      def build_message(method, params)
        { method: method, params: params }.merge(id: next_command_id)
      end

      def next_command_id
        @command_id += 1
      end
    end
  end
end
