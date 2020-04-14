# frozen_string_literal: true

require "bundler/setup"
require "rspec"

PROJECT_ROOT = File.expand_path("..", __dir__)
%w[/lib /spec].each { |p| $:.unshift(p) }

require "ferrum"
require "support/server"

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

  def with_external_browser(host: "127.0.0.1", port: 32001)
    opts = { host: host, port: port, window_size: [1400, 1400], headless: true }
    process = Ferrum::Browser::Process.new(opts)

    begin
      process.start
      yield "http://#{host}:#{port}"
    ensure
      process.stop
    end
  end

  def with_xvfb_browser(host: "127.0.0.1", port: 32001)
    opts = { host: host, port: port, window_size: [1400, 1400], headless: :xvfb }
    process = Ferrum::Browser::Process.new(opts)
    begin
      process.start
      expect(process.environment.xvfb).to be_process_alive
      yield "http://#{host}:#{port}"
    ensure
      process.stop
    end

    expect(process.environment.xvfb).not_to be_process_alive
  end
end

RSpec.configure do |config|
  config.include_context "Global helpers"

  config.before(:suite) do
    @server = Ferrum::Server.boot

    begin
      browser = Ferrum::Browser.new(process_timeout: 5)
      puts "Browser: #{browser.process.browser_version}"
      puts "Protocol: #{browser.process.protocol_version}"
      puts "V8: #{browser.process.v8_version}"
      puts "Webkit: #{browser.process.webkit_version}"
    ensure
      browser.quit
    end
  end

  config.before(:all) do
    base_url = Ferrum::Server.server.base_url
    @browser = Ferrum::Browser.new(base_url: base_url,
                                   process_timeout: 5)
  end

  config.after(:all) do
    @browser.quit
  end

  config.before(:each) do
    server&.wait_for_pending_requests
  end

  config.after(:each) do
    @browser.reset
  end
end
