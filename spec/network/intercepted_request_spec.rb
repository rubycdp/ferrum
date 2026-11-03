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

  describe "#status?" do
    it "returns true for the status the request was handled with" do
      handled = nil
      network.intercept
      page.on(:request) do |request|
        request.continue
        handled = request
      end

      page.go_to

      expect(handled.status?(:continued)).to be(true)
      expect(handled.status?("continued")).to be(true)
    end

    it "returns false for another status" do
      handled = nil
      network.intercept
      page.on(:request) do |request|
        request.continue
        handled = request
      end

      page.go_to

      expect(handled.status?(:aborted)).to be(false)
    end
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

  describe "#respond" do
    it "fulfills the request with the given body" do
      network.intercept
      page.on(:request) { |request| request.respond(body: "<h1>intercepted</h1>") }

      page.go_to("/non_existing")

      expect(network.status).to eq(200)
      expect(page.body).to include("intercepted")
    end

    it "fulfills the request with the given status code and headers" do
      network.intercept
      page.on(:request) do |request|
        request.respond(responseCode: 201, responseHeaders: { "X-Ferrum" => "yes" }, body: "created")
      end

      page.go_to

      expect(network.status).to eq(201)
      expect(network.response.headers).to include("X-Ferrum" => "yes")
      expect(page.body).to include("created")
    end

    it "marks the request as responded" do
      handled = nil
      network.intercept
      page.on(:request) do |request|
        request.respond(body: "ok")
        handled = request
      end

      page.go_to

      expect(handled.status?(:responded)).to be(true)
    end
  end

  describe "#continue" do
    it "lets the request through" do
      network.intercept
      page.on(:request) { |request, _index, _total| request.continue }

      page.go_to

      expect(network.status).to eq(200)
      expect(page.body).to include("Hello world!")
    end

    it "sends the request with the given overrides" do
      network.intercept
      page.on(:request) do |request|
        request.continue(headers: [{ name: "X-Ferrum", value: "overridden" }])
      end

      page.go_to("/headers")

      expect(page.body).to include("FERRUM: overridden")
    end
  end

  describe "#abort" do
    it "fails the request as blocked by the client" do
      network.intercept
      page.on(:request) { |request, _index, _total| request.abort }

      expect { page.go_to }.to raise_error(Ferrum::StatusError, /net::ERR_BLOCKED_BY_CLIENT/)
      expect(last_exchange.blocked?).to be(true)
    end
  end
end
