# frozen_string_literal: true

describe Ferrum::Network::Error do
  describe "#canceled?" do
    it "returns true for a canceled request" do
      page.go_to("/with_ajax_connection_canceled")

      expect(network.idle?).to be_falsey

      # FIXME: Hack to wait for content in the browser
      Ferrum::Utils::Attempt.with_retry(errors: RuntimeError, max: 10, wait: 0.1) do
        page.at_xpath("//h1[text() = 'Canceled']") || raise("Node not found")
      end

      expect(network.idle?).to be_truthy
      expect(last_exchange.error.canceled?).to be_truthy
    end
  end

  describe "#description" do
    it "returns the browser's message for the failure" do
      expect(server_error.description).to include("the server responded with a status of 500")
    end
  end

  describe "#time" do
    it "returns when the request failed" do
      started_at = Time.now - 1

      expect(server_error.time).to be_between(started_at, Time.now + 1)
    end
  end

  describe "#error_text" do
    it "returns Chrome's net error" do
      expect(server_error.error_text).to eq("net::ERR_HTTP_RESPONSE_CODE_FAILURE")
    end
  end

  def server_error
    expect { page.go_to("/server_error") }.to raise_error(Ferrum::StatusError)
    page.wait_until { page.network.traffic.first.error&.time }
    page.network.traffic.first.error
  end
end
