# frozen_string_literal: true

require "base64"
require "forwardable"
require "ferrum/page"
require "ferrum/contexts"
require "ferrum/browser/process"
require "ferrum/browser/client"

module Ferrum
  class Browser
    DEFAULT_TIMEOUT = ENV.fetch("FERRUM_DEFAULT_TIMEOUT", 5).to_i
    WINDOW_SIZE = [1024, 768].freeze
    BASE_URL_SCHEMA = %w[http https].freeze

    extend Forwardable
    delegate %i[default_context] => :contexts
    delegate %i[targets create_target create_page page pages windows] => :default_context
    delegate %i[goto back forward refresh reload
                at_css at_xpath css xpath current_url title body doctype
                headers cookies network
                mouse keyboard
                screenshot pdf viewport_size
                frames frame_by main_frame
                evaluate evaluate_on evaluate_async execute
                add_script_tag add_style_tag bypass_csp
                on] => :page
    delegate %i[default_user_agent] => :process

    attr_reader :client, :process, :contexts, :logger, :js_errors,
                :slowmo, :base_url, :options, :window_size
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
      @extensions ||= Array(@options[:extensions]).map do |ext|
        (ext.is_a?(Hash) && ext[:source]) || File.read(ext)
      end
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

    def reset
      @window_size = @original_window_size
      contexts.reset
    end

    def restart
      quit
      start
    end

    def quit
      @client.close
      @process.stop
      @client = @process = @contexts = nil
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
      @contexts = Contexts.new(self)
    end
  end
end
