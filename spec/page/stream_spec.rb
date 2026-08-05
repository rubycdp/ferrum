# frozen_string_literal: true

describe Ferrum::Page::Stream do
  subject(:streamer) { Object.new.extend(described_class) }

  describe "#stream" do
    let(:output) { String.new }
    let(:handle) { "stream-handle" }

    before do
      allow(streamer).to receive(:command).with("IO.close", handle: handle).and_return({})
    end

    it "reads and appends chunks until EOF" do
      expect(streamer).to receive(:command)
        .with("IO.read", handle: handle, size: described_class::STREAM_CHUNK)
        .twice
        .and_return(
          { "data" => "first", "base64Encoded" => false, "eof" => false },
          { "data" => "second", "base64Encoded" => false, "eof" => true }
        )

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

      streamer.stream(output: output, handle: handle)

      expect(output).to eq(binary)
    end

    it "propagates errors raised while reading the stream" do
      read_error = Ferrum::TimeoutError.new
      expect(streamer).to receive(:command)
        .with("IO.read", handle: handle, size: described_class::STREAM_CHUNK)
        .and_raise(read_error)

      expect do
        streamer.stream(output: output, handle: handle)
      end.to raise_error(Ferrum::TimeoutError) { |error| expect(error).to equal(read_error) }
    end
  end
end
