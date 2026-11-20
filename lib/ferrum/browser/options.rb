# frozen_string_literal: true

require "ferrum/log"

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
      DEFAULT_TIMEOUT = ENV.fetch("FERRUM_DEFAULT_TIMEOUT", 5).to_f
      PROCESS_TIMEOUT = ENV.fetch("FERRUM_PROCESS_TIMEOUT", 10).to_i

      PROTOCOL_TIMEOUT_REMOVED = "is ignored and will be removed in Ferrum 0.22. Internal commands have a fixed " \
                                 "timeout, :timeout bounds everything else."

      if ENV.key?("FERRUM_DEBUG")
        Utils::Deprecate.warn("FERRUM_DEBUG will be removed in Ferrum 0.22. Use FERRUM_LOG=* instead.")
      end
      if ENV.key?("FERRUM_PROTOCOL_TIMEOUT")
        Utils::Deprecate.warn("FERRUM_PROTOCOL_TIMEOUT #{PROTOCOL_TIMEOUT_REMOVED}")
      end

      attr_reader :window_size, :logger, :log, :ws_max_receive_size,
                  :js_errors, :base_url, :slowmo, :pending_connection_errors,
                  :url, :ws_url, :env, :process_timeout, :browser_path,
                  :save_path, :proxy, :port, :host, :headless, :incognito, :dockerize, :browser_options,
                  :ignore_default_browser_options, :xvfb, :flatten, :extensions
      attr_accessor :timeout, :default_user_agent

      def initialize(options = nil)
        @options = Hash(options&.dup)

        @port = @options.fetch(:port, BROWSER_PORT)
        @host = @options.fetch(:host, BROWSER_HOST)
        @timeout = @options.fetch(:timeout, DEFAULT_TIMEOUT)
        warn_protocol_timeout if @options.key?(:protocol_timeout)
        @window_size = @options.fetch(:window_size, WINDOW_SIZE)
        @js_errors = fetch_deprecated(
          :js_errors,
          "Uncaught exceptions are in the console, use page.console.select { |m| m.source == :exception } " \
          "or page.on(:console)."
        )
        @headless = @options.fetch(:headless, true)
        @incognito = @options.fetch(:incognito, true)
        @dockerize = @options.fetch(:dockerize, false)
        @flatten = @options.fetch(:flatten, true)
        warn_flatten unless @flatten
        @pending_connection_errors = fetch_deprecated(
          :pending_connection_errors, "Pass on_timeout: :raise to go_to instead: page.go_to(url, on_timeout: :raise)."
        )
        @process_timeout = @options.fetch(:process_timeout, PROCESS_TIMEOUT)
        @slowmo = @options[:slowmo].to_f

        @env = @options[:env]
        @xvfb = @options[:xvfb]
        @save_path = @options[:save_path]
        @browser_path = @options[:browser_path]
        @ws_max_receive_size = @options[:ws_max_receive_size]
        @ignore_default_browser_options = @options[:ignore_default_browser_options]

        @proxy = validate_proxy(@options[:proxy])
        @logger, @log = parse_logger(@options[:logger])
        @base_url = parse_base_url(@options[:base_url]) if @options[:base_url]
        @url = @options[:url].to_s if @options[:url]
        @ws_url = @options[:ws_url].to_s if @options[:ws_url]
        @extensions = Array(@options[:extensions]).map { |e| read_extension(e) }.freeze

        @options = @options.merge(window_size: @window_size).freeze
        @browser_options = @options.fetch(:browser_options, {}).freeze
      end

      #
      # Deprecated, will be removed in Ferrum 0.22. Internal commands have a fixed timeout.
      #
      # @return [Integer]
      #   {Client::PROTOCOL_TIMEOUT}.
      #
      def protocol_timeout
        warn_protocol_timeout
        Client::PROTOCOL_TIMEOUT
      end

      #
      # Deprecated, will be removed in Ferrum 0.22. The value is ignored.
      #
      # @param [Numeric] value
      #
      # @return [Numeric]
      #
      def protocol_timeout=(value)
        warn_protocol_timeout
        value
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
      # Adds an extension to run in every new document, before the document's own scripts. Applies to pages and
      # iframes attached after the call: pages already open keep the extensions they were attached with.
      #
      # @param [String, Hash] extension
      #   A path to a JS file, or `{ source: "..." }`.
      #
      # @return [Array<String>]
      #   JS source code of every extension.
      #
      # @raise [Errno::ENOENT]
      #   If the file doesn't exist.
      #
      # @example
      #   browser.add_extension("/path/to/stub.js")
      #   browser.add_extension(source: "window.secret = 'top'")
      #
      def add_extension(extension)
        @extensions = [*@extensions, read_extension(extension)].freeze
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

      def warn_protocol_timeout
        Utils::Deprecate.warn(":protocol_timeout #{PROTOCOL_TIMEOUT_REMOVED}", user_code: true)
      end

      def warn_flatten
        Utils::Deprecate.warn(
          "flatten: false will be removed in Ferrum 0.22. Every page will share the browser's websocket connection.",
          user_code: true
        )
      end

      def fetch_deprecated(name, instead)
        return false unless @options.key?(name)

        Utils::Deprecate.warn(":#{name} will be removed in Ferrum 0.22. #{instead}", user_code: true)
        @options[name]
      end

      def read_extension(extension)
        (extension.is_a?(Hash) && extension[:source]) || File.read(extension)
      end

      def parse_logger(logger)
        value = ENV.fetch("FERRUM_LOG") { "*" if ENV.key?("FERRUM_DEBUG") }
        settings = value ? Log.parse(value) : {}
        logger ||= $stdout.tap { |s| s.sync = true } if value && settings
        return [logger, nil] unless logger && settings

        [logger, Log.new(logger, **settings, format: Log.parse_format(ENV.fetch("FERRUM_LOG_FORMAT", nil)),
                                             color: Log.parse_color(ENV.fetch("FERRUM_LOG_COLOR", nil)))]
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
