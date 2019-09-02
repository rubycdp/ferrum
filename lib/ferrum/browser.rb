# frozen_string_literal: true

require "base64"
require "forwardable"
require "ferrum/page"
require "ferrum/targets"
require "ferrum/browser/process"
require "ferrum/browser/client"
require "ferrum/browser/api/screenshot"
require "ferrum/browser/api/intercept"

module Ferrum
  class Browser
    TIMEOUT = 5
    WINDOW_SIZE = [1024, 768].freeze
    BASE_URL_SCHEMA = %w[http https].freeze

    include API::Screenshot, API::Intercept
    extend Forwardable

    attr_reader :window_size

    delegate on: :@client
    delegate %i[window_handle window_handles switch_to_window
                open_new_window close_window within_window page] => :targets
    delegate %i[goto back forward refresh status
                at_css at_xpath css xpath current_url title body
                headers cookies network_traffic clear_network_traffic response_headers
                mouse keyboard scroll_to
                evaluate evaluate_on evaluate_async execute
                frame_url frame_title switch_to_frame
                find_modal accept_confirm dismiss_confirm accept_prompt dismiss_prompt reset_modals
                authorize proxy_authorize] => :page

    attr_reader :process, :logger, :js_errors, :slowmo, :base_url,
                :url_blacklist, :url_whitelist, :options
    attr_writer :timeout

    def initialize(options = nil)
      options ||= {}

      @client = nil
      @window_size = options.fetch(:window_size, WINDOW_SIZE)
      @original_window_size = @window_size

      @options = Hash(options.merge(window_size: @window_size))
      @logger, @timeout = @options.values_at(:logger, :timeout)
      @js_errors = @options.fetch(:js_errors, false)
      @slowmo = @options[:slowmo].to_i

      if @options.key?(:base_url)
        self.base_url = @options[:base_url]
      end

      self.url_blacklist = @options[:url_blacklist]
      self.url_whitelist = @options[:url_whitelist]

      if ENV["FERRUM_DEBUG"] && !@logger
        STDOUT.sync = true
        @logger = STDOUT
        @options[:logger] = @logger
      end

      @options.freeze

      start
    end

    def base_url=(value)
      parsed = Addressable::URI.parse(value)
      unless BASE_URL_SCHEMA.include?(parsed.normalized_scheme)
        raise "Set `base_url` should be absolute and include schema: #{BASE_URL_SCHEMA}"
      end

      @base_url = parsed
    end

    def extensions
      @extensions ||= Array(@options[:extensions]).map { |p| File.read(p) }
    end

    def timeout
      @timeout || TIMEOUT
    end

    def command(*args)
      @client.command(*args)
    rescue DeadBrowserError
      restart
      raise
    end

    def clear_memory_cache
      page.command("Network.clearBrowserCache")
    end

    def reset
      @zoom_factor = nil
      @window_size = @original_window_size
      targets.reset
    end

    def restart
      quit
      start
    end

    def quit
      @client.close
      @process.stop
      @client = @process = @targets = nil
    end

    def targets
      @targets ||= Targets.new(self)
    end

    def resize(**options)
      @window_size = [options[:width], options[:height]]
      page.resize(**options)
    end

    def crash
      command("Browser.crash")
    end

    private

    def start
      @process = Process.start(@options)
      @client = Client.new(self, @process.ws_url, 0, false)
    end
  end
end
