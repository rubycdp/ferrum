# frozen_string_literal: true

describe Ferrum::Network::Request do
  describe "#response_expected?" do
    it "returns true for document requests" do
      request = Ferrum::Network::Request.new({"type" => "Document"})

      expect(request.response_expected?).to be(true)
    end

    it "returns false for ping requests" do
      request = Ferrum::Network::Request.new({"type" => "Ping"})

      expect(request.response_expected?).to be(false)
    end
  end
end
