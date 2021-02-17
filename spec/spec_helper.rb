# frozen_string_literal: true

require "bundler/setup"
require "rspec"

PROJECT_ROOT = File.expand_path("..", __dir__)
%w[/lib /spec].each { |p| $:.unshift(p) }

require "ferrum"
require "support/server"
require "support/global_helpers"

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
    options = { base_url: base_url, process_timeout: 5 }

    if ENV["CI"]
      FERRUM_LOGGER = StringIO.new
      options.merge!(logger: FERRUM_LOGGER)
    end

    @browser = Ferrum::Browser.new(**options)
  end

  config.after(:all) do
    @browser.quit
  end

  config.before(:each) do
    server&.wait_for_pending_requests

    if ENV["CI"]
      FERRUM_LOGGER.truncate(0)
      FERRUM_LOGGER.rewind
    end
  end

  config.after(:each) do |example|
    if ENV["CI"] && example.exception
      save_exception_aftifacts(browser, example.metadata)
    end

    @browser.reset
  end

  def save_exception_aftifacts(browser, meta)
    time_now = Time.now
    filename = File.basename(meta[:file_path])
    line_number = meta[:line_number]
    timestamp = "#{time_now.strftime("%Y-%m-%d-%H-%M-%S.")}#{"%03d" % (time_now.usec/1000).to_i}"

    screenshot_name = "screenshot-#{filename}-#{line_number}-#{timestamp}.png"
    screenshot_path = "#{ENV["CIRCLE_ARTIFACTS"]}/screenshots/#{screenshot_name}"
    browser.screenshot(path: screenshot_path, full: true)

    log_name = "ferrum-#{filename}-#{line_number}-#{timestamp}.txt"
    log_path = "#{ENV["CIRCLE_ARTIFACTS"]}/logs/#{log_name}"
    File.open(log_path, "wb") { |file| file.write(FERRUM_LOGGER.string) }
  end
end
