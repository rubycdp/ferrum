# frozen_string_literal: true

module Ferrum
  class Page
    #
    # Reads a CDP `IO` stream handle (e.g. from `Page.printToPDF` or
    # `Tracing.tracingComplete`) in chunks and writes its contents to a file
    # on disk or accumulates it in memory.
    #
    module Stream
      STREAM_CHUNK = 128 * 1024

      #
      # Reads a CDP `IO` stream to a file on disk, or into memory when no
      # path is given.
      #
      # @param [String, nil] path
      #   The path to save the stream's contents to. When `nil` the contents
      #   are returned in memory instead.
      #
      # @param [Symbol] encoding
      #   `:base64` or `:binary`. Only used when `path` is `nil`.
      #
      # @param [String] handle
      #   The CDP `IO` stream handle to read from.
      #
      # @return [Boolean, String]
      #   `true` when saved to disk, otherwise the stream's contents.
      #
      def stream_to(path:, encoding:, handle:)
        if path.nil?
          stream_to_memory(encoding: encoding, handle: handle)
        else
          stream_to_file(path: path, handle: handle)
        end
      end

      #
      # Reads a CDP `IO` stream and writes its contents to a file on disk.
      #
      # @param [String] path
      #   The path to save the stream's contents to.
      #
      # @param [String] handle
      #   The CDP `IO` stream handle to read from.
      #
      # @return [Boolean]
      #
      def stream_to_file(path:, handle:)
        File.open(path, "wb") { |f| stream(output: f, handle: handle) }
        true
      end

      #
      # Reads a CDP `IO` stream into memory.
      #
      # @param [Symbol] encoding
      #   `:base64` to Base64-encode the result, `:binary` to return it as is.
      #
      # @param [String] handle
      #   The CDP `IO` stream handle to read from.
      #
      # @return [String]
      #
      def stream_to_memory(encoding:, handle:)
        data = String.new # Mutable string has << and compatible to File
        stream(output: data, handle: handle)
        encoding == :base64 ? Base64.encode64(data) : data
      end

      #
      # Reads a CDP `IO` stream in chunks, writing each chunk to the given
      # output until the stream is exhausted.
      #
      # @param [#<<] output
      #   Anything that responds to `#<<`, e.g. an open `File` or a `String`.
      #
      # @param [String] handle
      #   The CDP `IO` stream handle to read from.
      #
      # @return [void]
      #
      def stream(output:, handle:)
        loop do
          result = command("IO.read", handle: handle, size: STREAM_CHUNK)
          chunk = result.fetch("data")
          chunk = Base64.decode64(chunk) if result["base64Encoded"]
          output << chunk
          break if result["eof"]
        end
      end
    end
  end
end
