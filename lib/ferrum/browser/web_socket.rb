# frozen_string_literal: true

require "json"
require "socket"
require "websocket/driver"

module Ferrum
  class Browser
    class WebSocket
      WEBSOCKET_BUG_SLEEP = 0.01

      attr_reader :url, :messages

      def initialize(url, logger)
        @url      = url
        @logger   = logger
        uri       = URI.parse(@url)
        @sock     = TCPSocket.new(uri.host, uri.port)
        @driver   = ::WebSocket::Driver.client(self)
        @messages = Queue.new

        @driver.on(:open,    &method(:on_open))
        @driver.on(:message, &method(:on_message))
        @driver.on(:close,   &method(:on_close))

        @thread = Thread.new do
          begin
            while data = @sock.readpartial(512)
              @driver.parse(data)
            end
          rescue EOFError, Errno::ECONNRESET
            @messages.close
          end
        end

        @thread.priority = 1

        @driver.start
      end

      def on_open(_event)
        # https://github.com/faye/websocket-driver-ruby/issues/46
        sleep(WEBSOCKET_BUG_SLEEP)
      end

      def on_message(event)
        data = JSON.parse(event.data)
        @messages.push(data)
        @logger&.puts("    ◀ #{event.data}\n")
      end

      def on_close(_event)
        @messages.close
        @thread.kill
      end

      def send_message(data)
        json = data.to_json
        @driver.text(json)
        @logger&.puts("\n\n▶ #{json}")
      end

      def write(data)
        @sock.write(data)
      end

      def close
        @driver.close
      end
    end
  end
end
