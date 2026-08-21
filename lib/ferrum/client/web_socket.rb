# frozen_string_literal: true

require "json"
require "socket"
require "websocket/driver"

module Ferrum
  class Client
    #
    # Low-level WebSocket connection to the browser's CDP endpoint. Opens
    # the raw TCP/TLS socket, drives the `websocket-driver` handshake and
    # framing, and exposes a queue of parsed incoming messages alongside
    # methods to send commands and close the connection.
    #
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

        if port == 443 || url.scheme == "wss"
          tcp = TCPSocket.new(uri.host, port)
          ssl_context = OpenSSL::SSL::SSLContext.new
          @sock = OpenSSL::SSL::SSLSocket.new(tcp, ssl_context)
          @sock.sync_close = true
          @sock.connect
        else
          @sock = TCPSocket.new(uri.host, port)
        end

        max_receive_size ||= ::WebSocket::Driver::MAX_LENGTH
        @driver = ::WebSocket::Driver.client(self, max_length: max_receive_size)
        # websocket-driver holds no locks and is called from many threads: commands from
        # callers, pong/close replies from the reader. One lock keeps frames from interleaving.
        @driver_mutex = Mutex.new
        @messages = Queue.new

        @screenshot_commands = Concurrent::Hash.new if SKIP_LOGGING_SCREENSHOTS

        @driver.on(:open,    &method(:on_open))
        @driver.on(:message, &method(:on_message))
        @driver.on(:close,   &method(:on_close))

        start

        @driver_mutex.synchronize { @driver.start }
      end

      #
      # Handles the driver's `:open` event.
      #
      # @return [void]
      #
      def on_open(_event)
        # https://github.com/faye/websocket-driver-ruby/issues/46
        sleep(WEBSOCKET_BUG_SLEEP)
      end

      #
      # Handles the driver's `:message` event: parses the incoming frame
      # as JSON and pushes it onto {#messages}. Malformed payloads are
      # dropped rather than raised, to avoid crashing the reader thread.
      #
      # @return [void]
      #
      def on_message(event)
        data = safely_parse_json(event.data)
        output = event.data
        if SKIP_LOGGING_SCREENSHOTS && @screenshot_commands[data&.dig("id")]
          @screenshot_commands.delete(data&.dig("id"))
          output.sub!(/{"data":"[^"]*"}/, %("Set FERRUM_LOGGING_SCREENSHOTS=true to see screenshots in Base64"))
        end

        @logger&.puts("    ◀ #{Utils::ElapsedTime.elapsed_time} #{output}\n")

        # If we couldn't parse JSON data for some reason (parse error or deeply nested object) we
        # don't push response to @messages. Worse that could happen we raise timeout error due to command didn't return
        # anything or skip the background notification, but at least we don't crash the thread that crashes the main
        # thread and the application.
        @messages.push(data) if data
      end

      #
      # Handles the driver's `:close` event: closes the message queue and
      # underlying socket, then kills the reader thread.
      #
      # @return [void]
      #
      def on_close(_event)
        @messages.close
        @sock.close
        @thread.kill
      end

      #
      # Serializes a CDP command to JSON and sends it as a websocket text
      # frame.
      #
      # @param [Hash] data
      #   The message to send, must include an `:id` key.
      #
      # @return [void]
      #
      def send_message(data)
        @screenshot_commands[data[:id]] = true if SKIP_LOGGING_SCREENSHOTS

        json = data.to_json
        @driver_mutex.synchronize { @driver.text(json) }
        @logger&.puts("\n\n▶ #{Utils::ElapsedTime.elapsed_time} #{json}")
      end

      #
      # Writes raw bytes to the underlying socket. Called by
      # `websocket-driver` to emit frames. Closes {#messages} instead of
      # raising if the connection has already been torn down.
      #
      # @param [String] data
      #   The raw bytes to write.
      #
      # @return [void]
      #
      def write(data)
        @sock.write(data)
      rescue EOFError, Errno::ECONNRESET, Errno::EPIPE, IOError # rubocop:disable Lint/ShadowedException
        @messages.close
      end

      #
      # Closes the websocket connection by sending a close frame.
      #
      # @return [void]
      #
      def close
        @driver_mutex.synchronize { @driver.close }
      end

      private

      def start
        @thread = Utils::Thread.spawn do
          loop do
            data = @sock.readpartial(512)
            break unless data

            @driver_mutex.synchronize { @driver.parse(data) }
          end
        rescue EOFError, Errno::ECONNRESET, Errno::EPIPE, IOError # rubocop:disable Lint/ShadowedException
          @messages.close
        end
      end

      def safely_parse_json(data)
        JSON.parse(data, max_nesting: false)
      rescue JSON::NestingError
        # nop
      rescue JSON::ParserError
        safely_parse_escaped_json(data)
      end

      def safely_parse_escaped_json(data)
        unescaped_unicode =
          data.gsub(/\\u([\da-fA-F]{4})/) { |_| [::Regexp.last_match(1)].pack("H*").unpack("n*").pack("U*") }
        escaped_data = unescaped_unicode.encode("UTF-8", "UTF-8", undef: :replace, invalid: :replace, replace: "?")
        JSON.parse(escaped_data, max_nesting: false)
      rescue JSON::ParserError
        # nop
      end
    end
  end
end
