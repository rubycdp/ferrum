# frozen_string_literal: true

describe Ferrum::Network::AuthRequest do
  subject(:request) { described_class.new(nil, params) }

  let(:url) { "https://example.com/img/pattern.svg?1" }
  let(:params) do
    {
      "requestId" => "interception-id",
      "request" => { "url" => url }
    }
  end

  describe "#navigation_request?" do
    it "returns true for a document request" do
      request = described_class.new(nil, params.merge("resourceType" => "Document"))

      expect(request.navigation_request?).to be(true)
    end

    it "returns false for a subresource request" do
      request = described_class.new(nil, params.merge("resourceType" => "Script"))

      expect(request.navigation_request?).to be(false)
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

  describe "#continue" do
    it "answers the auth challenge with the given response" do
      network.intercept
      page.on(:request) { |request, _index, _total| request.continue }
      page.on(:auth) do |request, _index, _total|
        request.continue(authChallengeResponse: { response: "ProvideCredentials", username: "login", password: "pass" })
      end

      page.go_to("/basic_auth")

      expect(network.status).to eq(200)
      expect(page.body).to include("Welcome, authenticated client")
    end
  end

  describe "#abort" do
    it "cancels the auth challenge and lets the page load the unauthorized response" do
      network.intercept
      page.on(:request) { |request, _index, _total| request.continue }
      page.on(:auth) { |request, _index, _total| request.abort }

      page.go_to("/basic_auth")

      expect(network.status).to eq(401)
      expect(page.body).not_to include("Welcome, authenticated client")
    end
  end

  describe "#url" do
    it "returns the url of the request" do
      expect(auth_request("/basic_auth").url).to eq(base_url("/basic_auth"))
    end
  end

  describe "#method" do
    it "returns the HTTP method of the request" do
      expect(auth_request("/basic_auth").method).to eq("GET")
    end
  end

  describe "#headers" do
    it "returns the headers of the request" do
      page.headers.set("X-Ferrum" => "yes")

      expect(auth_request("/basic_auth").headers).to include("X-Ferrum" => "yes")
    end
  end

  def auth_request(path)
    challenged = nil
    network.intercept
    page.on(:request) { |request, _index, _total| request.continue }
    page.on(:auth) do |request, _index, _total|
      challenged ||= request
      request.continue(authChallengeResponse: { response: "CancelAuth" })
    end
    page.go_to(path)
    challenged
  end
end
