# frozen_string_literal: true

describe Ferrum::Page::Stream do
  subject(:streamer) { Object.new.extend(described_class) }

  describe "#stream" do
    let(:output) { String.new }
    let(:handle) { "stream-handle" }

    it "reads and appends chunks until EOF, then closes the stream" do
      expect(streamer).to receive(:command)
        .with("IO.read", handle: handle, size: described_class::STREAM_CHUNK)
        .twice
        .and_return(
          { "data" => "first", "base64Encoded" => false, "eof" => false },
          { "data" => "second", "base64Encoded" => false, "eof" => true }
        )
      expect(streamer).to receive(:command).with("IO.close", handle: handle).once.and_return({})

      streamer.stream(output: output, handle: handle)

      expect(output).to eq("firstsecond")
    end

    it "decodes Base64-encoded chunks" do
      binary = "\x00\xFFpdf".b
      expect(streamer).to receive(:command)
        .with("IO.read", handle: handle, size: described_class::STREAM_CHUNK)
        .once
        .and_return(
          { "data" => Base64.strict_encode64(binary), "base64Encoded" => true, "eof" => true }
        )
      expect(streamer).to receive(:command).with("IO.close", handle: handle).once.and_return({})

      streamer.stream(output: output, handle: handle)

      expect(output).to eq(binary)
    end

    it "propagates errors raised while reading the stream without attempting to close it" do
      read_error = Ferrum::TimeoutError.new
      expect(streamer).to receive(:command)
        .with("IO.read", handle: handle, size: described_class::STREAM_CHUNK)
        .and_raise(read_error)
      expect(streamer).not_to receive(:command).with("IO.close", any_args)

      expect do
        streamer.stream(output: output, handle: handle)
      end.to raise_error(Ferrum::TimeoutError) { |error| expect(error).to equal(read_error) }
    end

    it "propagates errors raised while writing output without attempting to close the stream" do
      write_error = IOError.new("write failed")
      output = Object.new
      allow(output).to receive(:<<).and_raise(write_error)
      expect(streamer).to receive(:command)
        .with("IO.read", handle: handle, size: described_class::STREAM_CHUNK)
        .and_return({ "data" => "chunk", "base64Encoded" => false, "eof" => true })
      expect(streamer).not_to receive(:command).with("IO.close", any_args)

      expect do
        streamer.stream(output: output, handle: handle)
      end.to raise_error(IOError) { |error| expect(error).to equal(write_error) }
    end

    it "propagates a close error after successfully reading the stream" do
      close_error = Ferrum::DeadBrowserError.new
      expect(streamer).to receive(:command)
        .with("IO.read", handle: handle, size: described_class::STREAM_CHUNK)
        .and_return({ "data" => "chunk", "base64Encoded" => false, "eof" => true })
      expect(streamer).to receive(:command)
        .with("IO.close", handle: handle)
        .once
        .and_raise(close_error)

      expect do
        streamer.stream(output: output, handle: handle)
      end.to raise_error(Ferrum::DeadBrowserError) { |error| expect(error).to equal(close_error) }
    end
  end

  describe "#close_stream" do
    it "is public so callers can close a stream they read some other way" do
      expect(streamer.public_methods).to include(:close_stream)
    end

    it "sends IO.close for the given handle" do
      expect(streamer).to receive(:command).with("IO.close", handle: "stream-handle").and_return({})

      streamer.close_stream(handle: "stream-handle")
    end
  end
end
