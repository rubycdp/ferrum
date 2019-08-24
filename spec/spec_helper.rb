# frozen_string_literal: true

require "bundler/setup"
require "rspec"

PROJECT_ROOT = File.expand_path("..", __dir__)
%w[/lib /spec].each { |p| $:.unshift(p) }

require "ferrum"
require "support/server"

RSpec.shared_context "Global helpers" do
  def base_url(*args)
    @server.base_url(*args)
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
end

RSpec.configure do |config|
  config.include_context "Global helpers"

  # config.before(:each) do
  #   @server&.wait_for_pending_requests
  # end

  config.before(:all) do
    @server = Ferrum::Server.boot
  end

  # config.after(:all) do
  # end
end
