# frozen_string_literal: true

require "json"
require "socket"
require "websocket/driver"

module Ferrum
  class Client
    class WebSocket
      WEBSOCKET_BUG_SLEEP = 0.05
      DEFAULT_PORTS = { "ws" => 80, "wss" => 443 }.freeze
      SKIP_LOGGING_SCREENSHOTS = !ENV["FERRUM_LOGGING_SCREENSHOTS"]

      attr_reader :url, :messages

      def initialize(url, max_receive_size, logger)
        @url    = url
        @logger = logger
        uri     = URI.parse(@url)
        port    = uri.port || DEFAULT_PORTS[uri.scheme]

        if port == 443
          tcp = TCPSocket.new(uri.host, port)
          ssl_context = OpenSSL::SSL::SSLContext.new
          @sock = OpenSSL::SSL::SSLSocket.new(tcp, ssl_context)
          @sock.sync_close = true
          @sock.connect
        else
          @sock = TCPSocket.new(uri.host, port)
        end

        max_receive_size ||= ::WebSocket::Driver::MAX_LENGTH
        @driver   = ::WebSocket::Driver.client(self, max_length: max_receive_size)
        @messages = Queue.new

        @screenshot_commands = Concurrent::Hash.new if SKIP_LOGGING_SCREENSHOTS

        @driver.on(:open,    &method(:on_open))
        @driver.on(:message, &method(:on_message))
        @driver.on(:close,   &method(:on_close))

        start

        @driver.start
      end

      def on_open(_event)
        # https://github.com/faye/websocket-driver-ruby/issues/46
        sleep(WEBSOCKET_BUG_SLEEP)
      end

      def on_message(event)
        data = JSON.parse(event.data)
        @messages.push(data)

        output = event.data
        if SKIP_LOGGING_SCREENSHOTS && @screenshot_commands[data["id"]]
          @screenshot_commands.delete(data["id"])
          output.sub!(/{"data":"(.*)"}/, %("Set FERRUM_LOGGING_SCREENSHOTS=true to see screenshots in Base64"))
        end

        @logger&.puts("    ◀ #{Utils::ElapsedTime.elapsed_time} #{output}\n")
      end

      def on_close(_event)
        @messages.close
        @sock.close
        @thread.kill
      end

      def send_message(data)
        @screenshot_commands[data[:id]] = true if SKIP_LOGGING_SCREENSHOTS

        json = data.to_json
        @driver.text(json)
        @logger&.puts("\n\n▶ #{Utils::ElapsedTime.elapsed_time} #{json}")
      end

      def write(data)
        @sock.write(data)
      rescue EOFError, Errno::ECONNRESET, Errno::EPIPE, IOError # rubocop:disable Lint/ShadowedException
        @messages.close
      end

      def close
        @driver.close
      end

      private

      def start
        @thread = Utils::Thread.spawn do
          loop do
            data = @sock.readpartial(512)
            break unless data

            @driver.parse(data)
          end
        rescue EOFError, Errno::ECONNRESET, Errno::EPIPE, IOError # rubocop:disable Lint/ShadowedException
          @messages.close
        end
      end
    end
  end
end
