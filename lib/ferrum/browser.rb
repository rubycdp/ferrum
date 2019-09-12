# frozen_string_literal: true

require "base64"
require "forwardable"
require "ferrum/page"
require "ferrum/targets"
require "ferrum/browser/process"
require "ferrum/browser/client"

module Ferrum
  class Browser
    DEFAULT_TIMEOUT = ENV.fetch("FERRUM_DEFAULT_TIMEOUT", 5).to_i
    WINDOW_SIZE = [1024, 768].freeze
    BASE_URL_SCHEMA = %w[http https].freeze

    extend Forwardable
    delegate %i[window_handle window_handles switch_to_window
                open_new_window close_window within_window page] => :targets
    delegate %i[goto back forward refresh status
                at_css at_xpath css xpath current_url title body
                headers cookies network_traffic clear_network_traffic response_headers
                intercept_request continue_request abort_request
                mouse keyboard
                screenshot pdf
                evaluate evaluate_on evaluate_async execute
                frame_url frame_title within_frame
                authorize
                on] => :page

    attr_reader :client, :process, :logger, :js_errors, :slowmo, :base_url,
                :options, :window_size
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
      @timeout || DEFAULT_TIMEOUT
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
      Ferrum.started
      @process = Process.start(@options)
      @client = Client.new(self, @process.ws_url, 0, false)
    end
  end
end
