# frozen_string_literal: true

RSpec.shared_context "Global helpers" do
  attr_reader :browser

  def server
    Ferrum::Server.server
  end

  def base_url(*args)
    server.base_url(*args)
  end

  def with_external_browser(host: "127.0.0.1", port: 32_001)
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
