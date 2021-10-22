RSpec.shared_context "Global helpers" do
  def server
    Ferrum::Server.server
  end

  def base_url(*args)
    server.base_url(*args)
  end

  def browser
    @browser
  end

  def page
    @page ||= @browser.create_page
  end

  def reset
    @browser.reset
    @page = nil
  end

  def with_external_browser(host: "127.0.0.1", port: 32001)
    options = { host: host, port: port, window_size: [1400, 1400], headless: true }
    process = Ferrum::Browser::Process.new(options)

    begin
      process.start
      yield "http://#{host}:#{port}"
    ensure
      process.stop
    end
  end
end
