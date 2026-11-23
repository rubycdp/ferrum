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

  describe "#timestamp" do
    it "returns the failure time in milliseconds and warns that it is deprecated" do
      error = server_error
      Ferrum::Utils::Deprecate.reset!

      expect { expect(error.timestamp).to be_within(1000).of(error.time.to_f * 1000) }
        .to output(/timestamp will be removed in Ferrum 0\.22.*called from #{__FILE__}/m).to_stderr
    end
  end

  describe "#monotonic_time" do
    it "returns Chrome's monotonic failure time and warns that it is deprecated" do
      error = server_error
      Ferrum::Utils::Deprecate.reset!

      expect { expect(error.monotonic_time).to be_a(Float) }
        .to output(/monotonic_time will be removed in Ferrum 0\.22.*called from #{__FILE__}/m).to_stderr
    end
  end

  def server_error
    expect { page.go_to("/server_error") }.to raise_error(Ferrum::StatusError)
    page.wait_until { page.network.traffic.first.error&.time }
    page.network.traffic.first.error
  end
end
