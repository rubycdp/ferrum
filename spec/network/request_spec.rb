# frozen_string_literal: true

describe Ferrum::Network::Request do
  describe "#id" do
    it "returns the id of the exchange" do
      page.go_to

      expect(last_exchange.request.id).to eq(last_exchange.id)
    end
  end

  describe "#type" do
    it "returns the resource type" do
      page.go_to("/with_js")

      expect(traffic.map { |e| e.request.type }).to eq(%w[Document Script Script Script])
    end
  end

  describe "#type?" do
    it "returns true for the matching type in any case" do
      page.go_to

      expect(last_exchange.request.type?(:document)).to be(true)
      expect(last_exchange.request.type?("DOCUMENT")).to be(true)
    end

    it "returns false for another type" do
      page.go_to

      expect(last_exchange.request.type?(:script)).to be(false)
    end
  end

  describe "#xhr?" do
    it "returns true for XHR requests" do
      page.go_to("/headers_with_ajax")

      expect(last_exchange.request.url).to end_with("/headers")
      expect(last_exchange.request.xhr?).to be(true)
    end

    it "returns false for document requests" do
      page.go_to("/headers_with_ajax")

      expect(first_exchange.request.xhr?).to be(false)
    end
  end

  describe "#frame_id" do
    it "returns the id of the frame the request was made from" do
      page.go_to

      expect(last_exchange.request.frame_id).to eq(page.main_frame.id)
    end
  end

  describe "#loader_id" do
    it "returns the id of the document loader" do
      page.go_to

      expect(last_exchange.request.loader_id).to eq(page.main_frame.loader_id)
    end
  end

  describe "#time" do
    it "returns the wall time the request was sent at" do
      started_at = Time.at(Time.now.to_i)

      page.go_to

      expect(last_exchange.request.time).to be_a(Time)
      expect(last_exchange.request.time).to be_between(started_at, Time.now)
    end
  end

  describe "#ping?" do
    it "returns false for document requests" do
      request = Ferrum::Network::Request.new({ "type" => "Document" })

      expect(request.ping?).to be(false)
    end

    it "returns true for ping requests" do
      request = Ferrum::Network::Request.new({ "type" => "Ping" })

      expect(request.ping?).to be(true)
    end
  end

  describe "#to_h" do
    it "returns the raw request params" do
      page.go_to

      expect(last_exchange.request.to_h).to include(
        "requestId" => last_exchange.id,
        "type" => "Document",
        "request" => hash_including("url" => base_url("/"), "method" => "GET")
      )
    end
  end
end
