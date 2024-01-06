# frozen_string_literal: true

describe Ferrum::Network::Request do
  describe "#ping?" do
    it "returns false for document requests" do
      request = Ferrum::Network::Request.new({"type" => "Document"})

      expect(request.ping?).to be(false)
    end

    it "returns true for ping requests" do
      request = Ferrum::Network::Request.new({"type" => "Ping"})

      expect(request.ping?).to be(true)
    end
  end
end
