# frozen_string_literal: true

describe Ferrum::Network::InterceptedRequest do
  subject(:request) { described_class.new(nil, params) }

  let(:url) { "https://example.com/img/pattern.svg?1" }
  let(:params) do
    {
      "requestId" => "interception-id",
      "request" => { "url" => url }
    }
  end

  describe "#match?" do
    it "matches regular expressions" do
      expect(request.match?(/pattern\.svg\?\d/)).to be(true)
    end

    it "matches exact strings" do
      expect(request.match?("https://example.com/img/pattern.svg?1")).to be(true)
    end

    it "does not treat string patterns as regular expressions" do
      expect(request.match?("pattern.svg?1")).to be(false)
    end
  end
end
