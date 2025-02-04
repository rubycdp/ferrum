# frozen_string_literal: true

describe Ferrum::Network::Error do
  it "#canceled?" do
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
