# frozen_string_literal: true

module Ferrum
  class Browser
    #
    # Resolves and normalizes the options hash passed to {Browser.new},
    # applying defaults for connection settings (host, port, timeouts),
    # window size, and other launch behavior. Used throughout the browser to
    # look up user-configured settings.
    #
    class Options
      BROWSER_PORT = "0"
      BROWSER_HOST = "127.0.0.1"
      WINDOW_SIZE = [1024, 768].freeze
      BASE_URL_SCHEMA = %w[http https].freeze
      DEFAULT_TIMEOUT = ENV.fetch("FERRUM_DEFAULT_TIMEOUT", 5).to_i
      DEFAULT_PROTOCOL_TIMEOUT = ENV.fetch("FERRUM_PROTOCOL_TIMEOUT", 30).to_i
      PROCESS_TIMEOUT = ENV.fetch("FERRUM_PROCESS_TIMEOUT", 10).to_i
      DEBUG_MODE = !ENV.fetch("FERRUM_DEBUG", nil).nil?

      attr_reader :window_size, :logger, :ws_max_receive_size,
                  :js_errors, :base_url, :slowmo, :pending_connection_errors,
                  :url, :ws_url, :env, :process_timeout, :browser_name, :browser_path,
                  :save_path, :proxy, :port, :host, :headless, :incognito, :dockerize, :browser_options,
                  :ignore_default_browser_options, :xvfb, :flatten
      attr_accessor :timeout, :protocol_timeout, :default_user_agent

      def initialize(options = nil)
        @options = Hash(options&.dup)

        @port = @options.fetch(:port, BROWSER_PORT)
        @host = @options.fetch(:host, BROWSER_HOST)
        @timeout = @options.fetch(:timeout, DEFAULT_TIMEOUT)
        @protocol_timeout = @options.fetch(:protocol_timeout, DEFAULT_PROTOCOL_TIMEOUT)
        @window_size = @options.fetch(:window_size, WINDOW_SIZE)
        @js_errors = @options.fetch(:js_errors, false)
        @headless = @options.fetch(:headless, true)
        @incognito = @options.fetch(:incognito, true)
        @dockerize = @options.fetch(:dockerize, false)
        @flatten = @options.fetch(:flatten, true)
        @pending_connection_errors = @options.fetch(:pending_connection_errors, false)
        @process_timeout = @options.fetch(:process_timeout, PROCESS_TIMEOUT)
        @slowmo = @options[:slowmo].to_f

        @env = @options[:env]
        @xvfb = @options[:xvfb]
        @save_path = @options[:save_path]
        @browser_name = @options[:browser_name]
        @browser_path = @options[:browser_path]
        @ws_max_receive_size = @options[:ws_max_receive_size]
        @ignore_default_browser_options = @options[:ignore_default_browser_options]

        @proxy = validate_proxy(@options[:proxy])
        @logger = parse_logger(@options[:logger])
        @base_url = parse_base_url(@options[:base_url]) if @options[:base_url]
        @url = @options[:url].to_s if @options[:url]
        @ws_url = @options[:ws_url].to_s if @options[:ws_url]

        @options = @options.merge(window_size: @window_size).freeze
        @browser_options = @options.fetch(:browser_options, {}).freeze
      end

      #
      # Sets the base URL relative navigations are resolved against.
      #
      # @param [String] value
      #   An absolute URL including scheme, e.g. `"https://example.com"`.
      #
      # @return [Addressable::URI]
      #
      def base_url=(value)
        @base_url = parse_base_url(value)
      end

      #
      # JS source to preload into the browser, read from `:extensions` option.
      #
      # @return [Array<String>]
      #   JS source code for each configured extension.
      #
      def extensions
        @extensions ||= Array(@options[:extensions]).map do |extension|
          (extension.is_a?(Hash) && extension[:source]) || File.read(extension)
        end
      end

      #
      # Validates the `:proxy` option, if given.
      #
      # @param [Hash, nil] options
      #   The `:proxy` option as passed to {#initialize}.
      #
      # @return [Hash, nil]
      #   The same `options`, unchanged.
      #
      # @raise [ArgumentError]
      #   If `options` is not a `Hash`, or is a `Hash` without `:host` or `:port`.
      #
      def validate_proxy(options)
        return unless options

        raise ArgumentError, "proxy options must be a Hash" unless options.is_a?(Hash)

        if options[:host].nil? && options[:port].nil?
          raise ArgumentError, "proxy options must be a Hash with at least :host | :port"
        end

        options
      end

      #
      # Raw options hash used to initialize the browser.
      #
      # @return [Hash{Symbol => Object}]
      #
      def to_h
        @options
      end

      private

      def parse_logger(logger)
        return logger if logger

        !logger && DEBUG_MODE ? $stdout.tap { |s| s.sync = true } : logger
      end

      def parse_base_url(value)
        parsed = Addressable::URI.parse(value)
        unless BASE_URL_SCHEMA.include?(parsed&.normalized_scheme)
          raise ArgumentError, "`base_url` should be absolute and include schema: #{BASE_URL_SCHEMA.join(' | ')}"
        end

        parsed
      end
    end
  end
end
