# frozen_string_literal: true

describe Ferrum::Network::Exchange do
  describe "#url" do
    it "returns url of the request" do
      page.go_to

      expect(last_exchange.url).to eq("http://127.0.0.1:#{server.port}/")
    end

    it "returns nil when request is blank" do
      page.go_to

      allow(last_exchange).to receive(:request) { nil }
      expect(last_exchange.url).to be_nil
    end
  end

  describe "#id" do
    it "returns an id" do
      page.go_to

      expect(last_exchange.id).to be
      expect(last_exchange.id).to be_a(String)
    end
  end

  describe "#intercepted_request" do
    it "returns request" do
      network.intercept
      page.on(:request) { |r, _, _| r.continue }

      page.go_to

      expect(page.body).to include("Hello world!")
      expect(last_exchange.intercepted_request).to be
      expect(last_exchange.intercepted_request).to be_a(Ferrum::Network::InterceptedRequest)
    end

    it "modifies request" do
      network.intercept
      page.on(:request) { |r, _, _| r.continue(url: base_url("/foo")) }

      page.go_to

      expect(page.body).to include("Another World")
      expect(last_exchange.intercepted_request).to be
      expect(last_exchange.intercepted_request).to be_a(Ferrum::Network::InterceptedRequest)
    end
  end

  describe "#request" do
    it "returns request" do
      page.go_to

      expect(last_exchange.request).to be
      expect(last_exchange.request).to be_a(Ferrum::Network::Request)
    end
  end

  describe "#response" do
    it "returns request" do
      page.go_to

      expect(last_exchange.response).to be
      expect(last_exchange.response).to be_a(Ferrum::Network::Response)
    end
  end

  describe "#error" do
    it "captures refused connection errors" do
      page.go_to("/with_ajax_connection_refused")
      expect(page.at_xpath("//h1[text() = 'Error']")).to be

      expect(last_exchange.error).to be
      expect(last_exchange.error).to be_a(Ferrum::Network::Error)
      expect(last_exchange.response).to be_nil
      expect(network.idle?).to be true
    end
  end

  describe "#navigation_request?" do
    it "determines if exchange is navigational" do
      page.go_to

      expect(last_exchange.request).to be
      expect(last_exchange.navigation_request?(page.main_frame.id)).to be true
    end
  end

  describe "#blank?" do
    it "determines if exchange is empty" do
      page.go_to

      expect(last_exchange.request).to be
      expect(last_exchange.blank?).to be false
    end
  end

  describe "#blocked?" do
    it "determines if exchange was blocked" do
      network.intercept
      page.on(:request) { |r, _, _| r.abort }

      expect do
        page.go_to
      end.to raise_error(
        Ferrum::StatusError,
        %r{Request to http://127.0.0.1:#{server.port} failed \(net::ERR_BLOCKED_BY_CLIENT\)}
      )

      expect(page.body).not_to include("Hello world!")
      expect(last_exchange.blocked?).to be true
    end
  end

  describe "#finished?" do
    it "determines if exchange is fully finished" do
      page.go_to

      expect(last_exchange.finished?).to be true
    end

    it "returns true if an error occurred" do
      exchange = Ferrum::Network::Exchange.new(page, "1")

      expect(exchange.finished?).to be false
      exchange.error = Ferrum::Network::Error.new
      expect(exchange.finished?).to be true
    end

    it "returns true for ping requests" do
      exchange = Ferrum::Network::Exchange.new(page, "1")
      expect(exchange.finished?).to be false

      exchange.request = Ferrum::Network::Request.new({ "type" => "Ping" })
      expect(exchange.finished?).to be true
    end

    it "returns true for blob requests" do
      exchange = Ferrum::Network::Exchange.new(page, "1")
      expect(exchange.blob?).to be false
      expect(exchange.finished?).to be false

      exchange.request = Ferrum::Network::Request.new(
        {
          "type" => "Document",
          "request" => {
            "url" => "blob:null/75787aaf-a81f-4237-98d7-0d51fe6cfcba"
          }
        }
      )
      expect(exchange.blob?).to be true
      expect(exchange.finished?).to be true
    end
  end

  describe "#redirect?" do
    it "determines if exchange is a redirect" do
      page.go_to("/redirect_again")

      expect(first_exchange.response.redirect?).to be
    end
  end

  describe "#ping?" do
    it "determines if exchange is ping type" do
      exchange = Ferrum::Network::Exchange.new(page, "1")
      expect(exchange.ping?).to be false

      exchange.request = Ferrum::Network::Request.new({ "type" => "Ping" })
      expect(exchange.ping?).to be true
    end
  end

  describe "#pending?" do
    it "determines if exchange is not fully loaded" do
      allow(page).to receive(:timeout) { 2 }

      expect do
        page.go_to("/visit_timeout")
      end.to raise_error(
        Ferrum::PendingConnectionsError,
        %r{Request to http://.*/visit_timeout reached server, but there are still pending connections: http://.*/really_slow}
      )
      expect(last_exchange.pending?).to be true
    end

    it "classifies request if loader changes" do
      page.go_to("/with_slow_ajax_connection")
      xhr = page.network.traffic.find(&:pending?)

      expect(page.body).to include("Slow AJAX")
      expect(xhr.url).to include("really_slow")
      expect(xhr.unknown).to be_falsey
      expect(xhr).to be_pending

      page.go_to("/")

      expect(page.body).to include("Hello world!")
      expect(xhr.unknown).to be_truthy
      expect(xhr).not_to be_pending
    end
  end

  describe "#intercepted?" do
    it "determines if exchange is interrupted" do
      network.intercept
      page.on(:request) { |r, _, _| r.continue }

      page.go_to

      expect(last_exchange.intercepted_request).to be
      expect(last_exchange.intercepted?).to be true
    end
  end

  describe "#to_a" do
    it "returns request, response and error" do
      page.go_to

      triple = last_exchange.to_a

      expect(triple.size).to eq(3)
      expect(triple).to eq([last_exchange.request, last_exchange.response, nil])
    end
  end

  describe "#inspect" do
    it "returns string for debugging" do
      page.go_to

      expect(last_exchange.inspect).to match(/
        \#<Ferrum::Network::Exchange\s
        @id=".+?"\s
        @intercepted_request=nil\s
        @request=\#<Ferrum::Network::Request.+?>\s
        @response=\#<Ferrum::Network::Response.+?>\s
        @error=nil>
      /x)
    end
  end
end
