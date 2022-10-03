# frozen_string_literal: true

require "base64"
require "forwardable"
require "ferrum/page"
require "ferrum/proxy"
require "ferrum/contexts"
require "ferrum/browser/xvfb"
require "ferrum/browser/process"
require "ferrum/browser/client"
require "ferrum/browser/binary"
require "ferrum/browser/version_info"

module Ferrum
  class Browser
    DEFAULT_TIMEOUT = ENV.fetch("FERRUM_DEFAULT_TIMEOUT", 5).to_i
    WINDOW_SIZE = [1024, 768].freeze
    BASE_URL_SCHEMA = %w[http https].freeze

    extend Forwardable
    delegate %i[default_context] => :contexts
    delegate %i[targets create_target page pages windows] => :default_context
    delegate %i[go_to goto go back forward refresh reload stop wait_for_reload
                at_css at_xpath css xpath current_url current_title url title
                body doctype content=
                headers cookies network
                mouse keyboard
                screenshot pdf mhtml viewport_size
                frames frame_by main_frame
                evaluate evaluate_on evaluate_async execute evaluate_func
                add_script_tag add_style_tag bypass_csp
                on position position=
                playback_rate playback_rate=] => :page
    delegate %i[default_user_agent] => :process

    attr_reader :client, :process, :contexts, :logger, :js_errors, :pending_connection_errors,
                :slowmo, :base_url, :options, :window_size, :ws_max_receive_size, :proxy_options,
                :proxy_server
    attr_writer :timeout

    #
    # Initializes the browser.
    #
    # @param [Hash{Symbol => Object}, nil] options
    #   Additional browser options.
    #
    # @option options [Boolean] :headless (true)
    #   Set browser as headless or not.
    #
    # @option options [Boolean] :xvfb (false)
    #   Run browser in a virtual framebuffer.
    #
    # @option options [(Integer, Integer)] :window_size ([1024, 768])
    #   The dimensions of the browser window in which to test, expressed as a
    #   2-element array, e.g. `[1024, 768]`.
    #
    # @option options [Array<String, Hash>] :extensions
    #   An array of paths to files or JS source code to be preloaded into the
    #   browser e.g.: `["/path/to/script.js", { source: "window.secret = 'top'" }]`
    #
    # @option options [#puts] :logger
    #   When present, debug output is written to this object.
    #
    # @option options [Integer, Float] :slowmo
    #   Set a delay in seconds to wait before sending command.
    #   Usefull companion of headless option, so that you have time to see
    #   changes.
    #
    # @option options [Numeric] :timeout (5)
    #   The number of seconds we'll wait for a response when communicating with
    #   browser.
    #
    # @option options [Boolean] :js_errors
    #   When true, JavaScript errors get re-raised in Ruby.
    #
    # @option options [Boolean] :pending_connection_errors (true)
    #   When main frame is still waiting for slow responses while timeout is
    #   reached {PendingConnectionsError} is raised. It's better to figure out
    #   why you have slow responses and fix or block them rather than turn this
    #   setting off.
    #
    # @option options [:chrome, :firefox] :browser_name (:chrome)
    #   Sets the browser's name. **Note:** only experimental support for
    #   `:firefox` for now.
    #
    # @option options [String] :browser_path
    #   Path to Chrome binary, you can also set ENV variable as
    #   `BROWSER_PATH=some/path/chrome bundle exec rspec`.
    #
    # @option options [Hash] :browser_options
    #   Additional command line options, [see them all](https://peter.sh/experiments/chromium-command-line-switches/)
    #   e.g. `{ "ignore-certificate-errors" => nil }`
    #
    # @option options [Boolean] :ignore_default_browser_options
    #   Ferrum has a number of default options it passes to the browser,
    #   if you set this to `true` then only options you put in
    #   `:browser_options` will be passed to the browser, except required ones
    #   of course.
    #
    # @option options [Integer] :port
    #   Remote debugging port for headless Chrome.
    #
    # @option options [String] :host
    #   Remote debugging address for headless Chrome.
    #
    # @option options [String] :url
    #   URL for a running instance of Chrome. If this is set, a browser process
    #   will not be spawned.
    #
    # @option options [Integer] :process_timeout
    #   How long to wait for the Chrome process to respond on startup.
    #
    # @option options [Integer] :ws_max_receive_size
    #   How big messages to accept from Chrome over the web socket, in bytes.
    #   Defaults to 64MB. Incoming messages larger this will cause a
    #   {Ferrum::DeadBrowserError}.
    #
    # @option options [Hash] :proxy
    #   Specify proxy settings, [read more](https://github.com/rubycdp/ferrum#proxy).
    #
    # @option options [String] :save_path
    #   Path to save attachments with [Content-Disposition](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Disposition) header.
    #
    # @option options [Hash] :env
    #   Environment variables you'd like to pass through to the process.
    #
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

      if ENV.fetch("FERRUM_DEBUG", nil) && !@logger
        $stdout.sync = true
        @logger = $stdout
        @options[:logger] = @logger
      end

      @options.freeze

      start
    end

    #
    # Sets the base URL.
    #
    # @param [String] value
    #   The new base URL value.
    #
    # @return [String]
    #   The base URL value.
    #
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

    #
    # Closes browser tabs opened by the `Browser` instance.
    #
    # @example
    #   # connect to a long-running Chrome process
    #   browser = Ferrum::Browser.new(url: 'http://localhost:9222')
    #
    #   browser.go_to("https://github.com/")
    #
    #   # clean up, lest the tab stays there hanging forever
    #   browser.reset
    #
    #   browser.quit
    #
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

    #
    # Gets the version information from the browser.
    #
    # @return [VersionInfo]
    #
    # @since 0.13
    #
    def version
      VersionInfo.new(command("Browser.getVersion"))
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
