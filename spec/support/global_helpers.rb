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
    network.traffic.reject { |e| e.request&.to_h&.fetch("documentURL") == "chrome-error://chromewebdata/" }
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

  def web_socket_debugger_url(url)
    uri = Addressable::URI.parse(url)
    url = uri.join("/json/version").to_s
    JSON.parse(Net::HTTP.get(URI(url)))["webSocketDebuggerUrl"]
  rescue JSON::ParserError
    # nop
  end

  def wait_a_bit(duration = 0.2)
    Thread.pass && sleep(duration)
  end
end
