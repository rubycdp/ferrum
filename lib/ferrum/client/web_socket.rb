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
    # The socket is only ever touched by two threads: the reader reads it and
    # the writer writes it, both blocking. Callers and the driver only encode
    # frames and queue them for the writer, so no lock is held while waiting
    # on the socket and a browser that stops reading blocks nobody but the
    # writer. A frame chunk the browser doesn't take within the write timeout
    # closes the connection. JRuby can't mix a blocking read with
    # `write_nonblock` or `IO.select` from another thread on the same socket,
    # so neither is used.
    #
    class WebSocket
      WEBSOCKET_BUG_SLEEP = 0.05
      DEFAULT_PORTS = { "ws" => 80, "wss" => 443 }.freeze
      WRITE_CHUNK_SIZE = 64 * 1024
      ESCAPE_OR_LONE_SURROGATE = /\\u[dD][89abAB]\h{2}\\u[dD][c-fC-F]\h{2}|\\u([dD][89a-fA-F]\h{2})|\\./

      attr_reader :url, :messages

      # @return [String, nil]
      #   Why Ferrum closed the connection itself, `nil` if it didn't.
      attr_reader :close_reason

      def initialize(url, max_receive_size, log, write_timeout = nil)
        @url = url
        @log = log
        @write_timeout = write_timeout
        uri = URI.parse(@url)
        port = uri.port || DEFAULT_PORTS[uri.scheme]

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
        @mutex = Mutex.new
        @encoded = []
        @messages = Queue.new
        @outgoing = Queue.new

        @driver.on(:open,    &method(:on_open))
        @driver.on(:message, &method(:on_message))
        @driver.on(:close,   &method(:on_close))

        start
        start_writer

        drive { @driver.start }
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
        @log&.received(data, event.data, self)

        # If we couldn't parse JSON data for some reason (parse error or deeply nested object) we
        # don't push response to @messages. Worse that could happen we raise timeout error due to command didn't return
        # anything or skip the background notification, but at least we don't crash the thread that crashes the main
        # thread and the application.
        @messages.push(data) if data
      end

      #
      # Handles the driver's `:close` event: closes the message queue, lets the
      # writer send what's queued and close the socket, then kills the reader
      # thread.
      #
      # @return [void]
      #
      def on_close(_event)
        @messages.close
        queue_encoded
        @outgoing.close
        @thread.kill
      end

      #
      # Serializes a CDP command to JSON and queues it as a websocket text
      # frame. Returns without waiting for the frame to be written.
      #
      # @param [Hash] data
      #   The message to send, must include an `:id` key.
      #
      # @param [Numeric, nil] timeout
      #   How long the frame may wait in the queue. A frame still queued after
      #   that is dropped, nobody waits for its response anymore. `nil` keeps it
      #   until it's written.
      #
      # @return [void]
      #
      def send_message(data, timeout = nil)
        json = data.to_json
        deadline = Utils::ElapsedTime.monotonic_time + timeout if timeout
        drive(deadline) { @driver.text(json) }
        @log&.sent(data, self)
      end

      #
      # Collects the raw bytes of a frame. Called by `websocket-driver` to
      # emit frames, one call per frame, always from within the driver call
      # that queues them for the writer thread.
      #
      # @param [String] data
      #   The raw bytes of one frame.
      #
      # @return [void]
      #
      def write(data)
        @encoded << data
      end

      #
      # Closes the websocket connection by sending a close frame.
      #
      # @return [void]
      #
      def close
        drive { @driver.close }
      end

      #
      # Stops the writer and closes the underlying socket whether or not the
      # close handshake ever completed.
      #
      # {#close} only queues a close frame; the socket itself is closed by the
      # writer once {#on_close} runs, when the browser answers with a close
      # frame of its own. A browser that is already dead never answers, so without this
      # the socket stays open until GC finalizes it -- long enough to exhaust
      # the process's file descriptors when browsers are restarted in a loop.
      #
      # @return [void]
      #
      def force_close
        @outgoing.close
        @sock.close unless @sock.closed?
      rescue IOError, SystemCallError
        # nop
      end

      private

      def drive(deadline = nil)
        @mutex.synchronize do
          yield
          queue_encoded(deadline)
        end
      end

      def queue_encoded(deadline = nil)
        @encoded.each { |data| @outgoing << [data, deadline] }
      rescue ClosedQueueError
        @messages.close
      ensure
        @encoded.clear
      end

      def start_writer
        @writer = Utils::Thread.spawn do
          while (frame = @outgoing.pop)
            data, deadline = frame
            write_frame(data) unless deadline && Utils::ElapsedTime.monotonic_time > deadline
          end
        rescue EOFError, Errno::ECONNRESET, Errno::EPIPE, Errno::EBADF, IOError # rubocop:disable Lint/ShadowedException
          # The browser went away, nothing to report.
        rescue StandardError => e
          warn("Ferrum: websocket writer stopped, #{e.class}: #{e.message}\n  #{e.backtrace&.first}")
        ensure
          @messages.close
          force_close
        end
      end

      def write_frame(data)
        0.step(data.bytesize - 1, WRITE_CHUNK_SIZE) do |offset|
          watchdog = Concurrent::ScheduledTask.execute(@write_timeout) { abandon_stalled_write } if @write_timeout
          @sock.write(data.byteslice(offset, WRITE_CHUNK_SIZE))
        ensure
          watchdog&.cancel
        end
      end

      def abandon_stalled_write
        @close_reason = "Browser accepted no data for #{@write_timeout}s and is likely stuck, connection closed"
        @messages.close
        force_close
      end

      def start
        @thread = Utils::Thread.spawn do
          loop do
            data = @sock.readpartial(512)
            break unless data

            drive { @driver.parse(data) }
          end
        rescue EOFError, Errno::ECONNRESET, Errno::EPIPE, Errno::EBADF, IOError # rubocop:disable Lint/ShadowedException
          # The browser went away, nothing to report.
        rescue StandardError => e
          warn("Ferrum: websocket reader stopped, #{e.class}: #{e.message}\n  #{e.backtrace&.first}")
        ensure
          @messages.close
        end
      end

      def safely_parse_json(data)
        JSON.parse(data, max_nesting: false)
      rescue JSON::NestingError
        # nop
      rescue JSON::ParserError
        safely_parse_lone_surrogates(data)
      end

      def safely_parse_lone_surrogates(data)
        replaced = data.gsub(ESCAPE_OR_LONE_SURROGATE) { |escape| ::Regexp.last_match(1) ? "\\ufffd" : escape }
        JSON.parse(replaced, max_nesting: false)
      rescue JSON::ParserError
        # nop
      end
    end
  end
end
