# frozen_string_literal: true

require "bundler/setup"
require "rspec"

PROJECT_ROOT = File.expand_path("..", __dir__)
%w[/lib /spec].each { |p| $LOAD_PATH.unshift(p) }

require "ferrum"
require "support/server"
require "support/global_helpers"

# GA servers are slow it's better to increase
ENV["FERRUM_NEW_WINDOW_WAIT"] ||= "0.8" if ENV["CI"]

puts ""
command = Ferrum::Browser::Command.build({ window_size: [], ignore_default_browser_options: true }, nil)
puts `#{command.to_a.first} --version`
puts ""

RSpec.configure do |config|
  ferrum_logger = nil
  config.include_context "Global helpers"

  config.before(:suite) do
    @server = Ferrum::Server.boot
  end

  config.before(:all) do
    base_url = Ferrum::Server.server.base_url
    options = { base_url: base_url }
    options.merge!(headless: false) if ENV["HEADLESS"] == "false"

    if ENV["CI"]
      ferrum_logger = StringIO.new
      options.merge!(logger: ferrum_logger)
    end

    @browser = Ferrum::Browser.new(**options)
  end

  config.after(:all) do
    @browser.quit
  end

  config.before(:each) do
    server&.wait_for_pending_requests

    if ENV["CI"]
      ferrum_logger.truncate(0)
      ferrum_logger.rewind
    end
  end

  config.after(:each) do |example|
    save_exception_artifacts(browser, example.metadata) if ENV["CI"] && example.exception

    reset
  end

  def save_exception_artifacts(browser, meta)
    time_now = Time.now
    filename = File.basename(meta[:file_path])
    line_number = meta[:line_number]
    timestamp = time_now.strftime("%Y-%m-%d-%H-%M-%S.") + format("%03d", (time_now.usec / 1000).to_i)

    save_exception_log(browser, filename, line_number, timestamp)
    save_exception_screenshot(browser, filename, line_number, timestamp)
  end

  def save_exception_screenshot(browser, filename, line_number, timestamp)
    screenshot_name = "screenshot-#{filename}-#{line_number}-#{timestamp}.png"
    screenshot_path = "/tmp/ferrum/#{screenshot_name}"
    browser.screenshot(path: screenshot_path, full: true)
  rescue StandardError => e
    puts "#{e.class}: #{e.message}"
  end

  def save_exception_log(_browser, filename, line_number, timestamp)
    log_name = "logfile-#{filename}-#{line_number}-#{timestamp}.txt"
    File.open("/tmp/ferrum/#{log_name}", "wb") { |file| file.write(ferrum_logger.string) }
  rescue StandardError => e
    puts "#{e.class}: #{e.message}"
  end
end
