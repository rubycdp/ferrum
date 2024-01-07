# frozen_string_literal: true

RSpec.shared_context "Global helpers" do
  attr_reader :browser

  def server
    Ferrum::Server.server
  end

  def base_url(*args)
    server.base_url(*args)
  end

  def page
    @page ||= @browser.create_page
  end

  def network
    page.network
  end

  def traffic
    network.traffic.reject do |e|
      e.url&.match?("favicon.ico") ||
        e.request&.to_h&.fetch("documentURL") == "chrome-error://chromewebdata/"
    end
  end

  def first_exchange
    traffic.first
  end

  def last_exchange
    traffic.last
  end

  def reset
    @browser.reset
    @page = nil
  end

  def with_timeout(new_timeout)
    old_timeout = browser.timeout
    browser.timeout = new_timeout
    yield
  ensure
    browser.timeout = old_timeout
  end

  def with_external_browser(host: "127.0.0.1", port: 32_001)
    options = Ferrum::Browser::Options.new(host: host, port: port, window_size: [1400, 1400], headless: true)
    process = Ferrum::Browser::Process.new(options)

    begin
      process.start
      yield "http://#{host}:#{port}", process
    ensure
      process.stop
    end
  end
end
