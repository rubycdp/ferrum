# frozen_string_literal: true

module Ferrum
  module Utils
    module Stream
      STREAM_CHUNK = 128 * 1024

      module_function

      def fetch(path:, encoding:, &block)
        if path.nil?
          stream_to_memory(encoding: encoding, &block)
        else
          stream_to_file(path: path, &block)
        end
      end

      def stream_to_file(path:, &block)
        File.open(path, "wb") { |f| stream_to(f, &block) }
        true
      end

      def stream_to_memory(encoding:, &block)
        data = String.new("") # Mutable string has << and compatible to File
        stream_to(data, &block)
        encoding == :base64 ? Base64.encode64(data) : data
      end

      def stream_to(output, &block)
        loop do
          read_stream = lambda do |client:, handle:|
            client.command("IO.read", handle: handle, size: STREAM_CHUNK)
          end
          result = block.call(read_stream)
          data_chunk = result["data"]
          data_chunk = Base64.decode64(data_chunk) if result["base64Encoded"]
          output << data_chunk
          break if result["eof"]
        end
      end
    end
  end
end
