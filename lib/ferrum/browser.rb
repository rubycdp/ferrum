# frozen_string_literal: true

require "base64"
require "forwardable"
require "ferrum/page"
require "ferrum/proxy"
require "ferrum/contexts"
require "ferrum/browser/xvfb"
require "ferrum/browser/process"
require "ferrum/browser/client"

module Ferrum
  class Browser
    DEFAULT_TIMEOUT = ENV.fetch("FERRUM_DEFAULT_TIMEOUT", 5).to_i
    WINDOW_SIZE = [1024, 768].freeze
    BASE_URL_SCHEMA = %w[http https].freeze

    extend Forwardable
    delegate %i[default_context] => :contexts
    delegate %i[targets create_target page pages windows] => :default_context
    delegate %i[go_to back forward refresh reload stop wait_for_reload
                at_css at_xpath css xpath current_url current_title url title
                body doctype content=
                headers cookies network
                mouse keyboard
                screenshot pdf mhtml viewport_size
                frames frame_by main_frame
                evaluate evaluate_on evaluate_async execute evaluate_func
                add_script_tag add_style_tag bypass_csp
                on goto position position=
                playback_rate playback_rate=] => :page
    delegate %i[default_user_agent] => :process

    attr_reader :client, :process, :contexts, :logger, :js_errors, :pending_connection_errors,
                :slowmo, :base_url, :options, :window_size, :ws_max_receive_size, :proxy_options,
                :proxy_server
    attr_writer :timeout

    def initialize(options = nil)
      options ||= {}

      @client = nil
      @window_size = options.fetch(:window_size, WINDOW_SIZE)
      @original_window_size = @window_size

      @options = Hash(options.merge(window_size: @window_size))
      @logger, @timeout, @ws_max_receive_size =
        @options.values_at(:logger, :timeout, :ws_max_receive_size)
      @js_errors = @options.fetch(:js_errors, false)

      if @options[:proxy]
        @proxy_options = @options[:proxy]

        if @proxy_options[:server]
          @proxy_server = Proxy.start(**@proxy_options.slice(:host, :port, :user, :password))
          @proxy_options.merge!(host: @proxy_server.host, port: @proxy_server.port)
        end

        @options[:browser_options] ||= {}
        address = "#{@proxy_options[:host]}:#{@proxy_options[:port]}"
        @options[:browser_options].merge!("proxy-server" => address)
        @options[:browser_options].merge!("proxy-bypass-list" => @proxy_options[:bypass]) if @proxy_options[:bypass]
      end

      @pending_connection_errors = @options.fetch(:pending_connection_errors, true)
      @slowmo = @options[:slowmo].to_f

      self.base_url = @options[:base_url] if @options.key?(:base_url)

      if ENV["FERRUM_DEBUG"] && !@logger
        $stdout.sync = true
        @logger = $stdout
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

    def create_page(new_context: false)
      page = if new_context
               context = contexts.create
               context.create_page
             else
               default_context.create_page
             end

      block_given? ? yield(page) : page
    ensure
      if block_given?
        page.close
        context.dispose if new_context
      end
    end

    def extensions
      @extensions ||= Array(@options[:extensions]).map do |ext|
        (ext.is_a?(Hash) && ext[:source]) || File.read(ext)
      end
    end

    def evaluate_on_new_document(expression)
      extensions << expression
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
      Utils::ElapsedTime.start
      @process = Process.start(@options)
      @client = Client.new(self, @process.ws_url)
      @contexts = Contexts.new(self)
    end
  end
end
