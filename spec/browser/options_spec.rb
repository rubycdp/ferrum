# frozen_string_literal: true

describe Ferrum::Browser::Options do
  describe "#protocol_timeout" do
    it "defaults to a low value, sufficient for internal CDP bookkeeping" do
      options = described_class.new

      expect(options.protocol_timeout).to eq(Ferrum::Browser::Options::DEFAULT_PROTOCOL_TIMEOUT)
    end

    it "does not shrink when :timeout is lowered" do
      options = described_class.new(timeout: 0.1)

      expect(options.timeout).to eq(0.1)
      expect(options.protocol_timeout).to eq(Ferrum::Browser::Options::DEFAULT_PROTOCOL_TIMEOUT)
    end

    it "is configurable independently of :timeout" do
      options = described_class.new(timeout: 10, protocol_timeout: 60)

      expect(options.timeout).to eq(10)
      expect(options.protocol_timeout).to eq(60)
    end
  end
end
