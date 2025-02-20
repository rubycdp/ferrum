# frozen_string_literal: true

require "stringio"
require "logger"

describe Ferrum::Browser do
  it "logs requests and responses with native Logger" do
    custom_logger = Class.new do
      def initialize(logger)
        @logger = logger
      end

      def puts(*args)
        @logger << args
      end
    end
    file_path = "test.log"
    logger = custom_logger.new(Logger.new(file_path))
    browser = Ferrum::Browser.new(logger: logger)
    browser.body
    file_log = File.read(file_path)
    expect(file_log).to include("return document.documentElement?.outerHTML")
    expect(file_log).to include("<html><head></head><body></body></html>")
  ensure
    FileUtils.rm_f(file_path)
    browser.quit
  end

  it "logs requests and responses" do
    logger = StringIO.new
    browser = Ferrum::Browser.new(logger: logger)

    browser.body

    expect(logger.string).to include("return document.documentElement?.outerHTML")
    expect(logger.string).to include("<html><head></head><body></body></html>")
  ensure
    browser.quit
  end

  it "shows command line options passed" do
    browser = Ferrum::Browser.new(browser_options: { "blink-settings" => "imagesEnabled=false" })

    arguments = browser.command("Browser.getBrowserCommandLine")["arguments"]

    expect(arguments).to include("--blink-settings=imagesEnabled=false")
  ensure
    browser.quit
  end
end
