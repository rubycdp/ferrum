# frozen_string_literal: true

require "forwardable"
require "ferrum/mouse"
require "ferrum/keyboard"
require "ferrum/headers"
require "ferrum/cookies"
require "ferrum/dialog"
require "ferrum/network"
require "ferrum/page/frames"
require "ferrum/page/screenshot"
require "ferrum/browser/client"

module Ferrum
  class Page
    GOTO_WAIT = ENV.fetch("FERRUM_GOTO_WAIT", 0.1).to_f

    class Event < Concurrent::Event
      def iteration
        synchronize { @iteration }
      end

      def reset
        synchronize do
          @iteration += 1
          @set = false if @set
          @iteration
        end
      end
    end

    extend Forwardable
    delegate %i[at_css at_xpath css xpath
                current_url current_title url title body doctype set_content
                execution_id evaluate evaluate_on evaluate_async execute
                add_script_tag add_style_tag] => :main_frame

    include Frames, Screenshot

    attr_accessor :referrer
    attr_reader :target_id, :browser,
                :headers, :cookies, :network,
                :mouse, :keyboard, :event, :document_id

    def initialize(target_id, browser)
      @frames = {}
      @main_frame = Frame.new(nil, self) 
      @target_id, @browser = target_id, browser
      @event = Event.new.tap(&:set)

      host = @browser.process.host
      port = @browser.process.port
      ws_url = "ws://#{host}:#{port}/devtools/page/#{@target_id}"
      @client = Browser::Client.new(browser, ws_url, id_starts_with: 1000)

      @mouse, @keyboard = Mouse.new(self), Keyboard.new(self)
      @headers, @cookies = Headers.new(self), Cookies.new(self)
      @network = Network.new(self)

      subscribe
      prepare_page
    end

    def timeout
      @browser.timeout
    end

    def goto(url = nil)
      options = { url: combine_url!(url) }
      options.merge!(referrer: referrer) if referrer
      response = command("Page.navigate", wait: GOTO_WAIT, **options)
      # https://cs.chromium.org/chromium/src/net/base/net_error_list.h
      if %w[net::ERR_NAME_NOT_RESOLVED
            net::ERR_NAME_RESOLUTION_FAILED
            net::ERR_INTERNET_DISCONNECTED
            net::ERR_CONNECTION_TIMED_OUT].include?(response["errorText"])
        raise StatusError, options[:url]
      end
      response["frameId"]
    rescue TimeoutError
      pendings = network.traffic.select(&:pending?).map { |e| e.request.url }
      raise StatusError.new(options[:url], pendings) unless pendings.empty?
    end

    def close
      @headers.clear
      @browser.command("Target.closeTarget", targetId: @target_id)
      @client.close
    end

    def resize(width: nil, height: nil, fullscreen: false)
      result = @browser.command("Browser.getWindowForTarget", targetId: @target_id)
      @window_id, @bounds = result.values_at("windowId", "bounds")

      if fullscreen
        width, height = document_size
        @browser.command("Browser.setWindowBounds", windowId: @window_id, bounds: { windowState: "fullscreen" })
      else
        @browser.command("Browser.setWindowBounds", windowId: @window_id, bounds: { windowState: "normal" })
        @browser.command("Browser.setWindowBounds", windowId: @window_id, bounds: { width: width, height: height, windowState: "normal" })
      end

      command("Emulation.setDeviceMetricsOverride", slowmoable: true,
                                                    width: width,
                                                    height: height,
                                                    deviceScaleFactor: 1,
                                                    mobile: false,
                                                    fitWindow: false)
    end

    def refresh
      command("Page.reload", wait: timeout, slowmoable: true)
    end
    alias_method :reload, :refresh

    def stop
      command("Page.stopLoading", slowmoable: true)
    end

    def back
      history_navigate(delta: -1)
    end

    def forward
      history_navigate(delta: 1)
    end

    def bypass_csp(value = true)
      enabled = !!value
      command("Page.setBypassCSP", enabled: enabled)
      enabled
    end

    def command(method, wait: 0, slowmoable: false, **params)
      iteration = @event.reset if wait > 0
      sleep(@browser.slowmo) if slowmoable && @browser.slowmo > 0
      result = @client.command(method, params)

      if wait > 0
        @event.wait(wait) # Wait a bit after command and check if iteration has
                          # changed which means there was some network event for
                          # the main frame and it started to load new content.
        if iteration != @event.iteration
          set = @event.wait(@browser.timeout)
          raise TimeoutError unless set
        end
      end
      result
    end

    def on(name, &block)
      case name
      when :dialog
        @client.on("Page.javascriptDialogOpening") do |params, index, total|
          dialog = Dialog.new(self, params)
          block.call(dialog, index, total)
        end
      when :request
        @client.on("Fetch.requestPaused") do |params, index, total|
          request = Network::InterceptedRequest.new(self, params)
          exchange = network.select(request.network_id).last
          exchange ||= network.build_exchange(request.network_id)
          exchange.intercepted_request = request
          block.call(request, index, total)
        end
      when :auth
        @client.on("Fetch.authRequired") do |params, index, total|
          request = Network::AuthRequest.new(self, params)
          block.call(request, index, total)
        end
      else
        @client.on(name, &block)
      end
    end

    private

    def subscribe
      frames_subscribe
      network.subscribe

      if @browser.logger
        on("Runtime.consoleAPICalled") do |params|
          params["args"].each { |r| @browser.logger.puts(r["value"]) }
        end
      end

      if @browser.js_errors
        on("Runtime.exceptionThrown") do |params|
          # FIXME https://jvns.ca/blog/2015/11/27/why-rubys-timeout-is-dangerous-and-thread-dot-raise-is-terrifying/
          Thread.main.raise JavaScriptError.new(params.dig("exceptionDetails", "exception"))
        end
      end
    end

    def prepare_page
      command("Page.enable")
      command("Runtime.enable")
      command("DOM.enable")
      command("CSS.enable")
      command("Log.enable")
      command("Network.enable")

      if @browser.options[:save_path]
        command("Page.setDownloadBehavior", behavior: "allow", downloadPath: @browser.options[:save_path])
      end

      @browser.extensions.each do |extension|
        command("Page.addScriptToEvaluateOnNewDocument", source: extension)
      end

      inject_extensions

      width, height = @browser.window_size
      resize(width: width, height: height)

      response = command("Page.getNavigationHistory")
      if response.dig("entries", 0, "transitionType") != "typed"
        # If we create page by clicking links, submiting forms and so on it
        # opens a new window for which `frameStoppedLoading` event never
        # occurs and thus search for nodes cannot be completed. Here we check
        # the history and if the transitionType for example `link` then
        # content is already loaded and we can try to get the document.
        get_document_id
      end
    end

    def inject_extensions
      @browser.extensions.each do |extension|
        # https://github.com/GoogleChrome/puppeteer/issues/1443
        # https://github.com/ChromeDevTools/devtools-protocol/issues/77
        # https://github.com/cyrus-and/chrome-remote-interface/issues/319
        # We also evaluate script just in case because
        # `Page.addScriptToEvaluateOnNewDocument` doesn't work in popups.
        command("Runtime.evaluate", expression: extension,
                                    contextId: execution_id,
                                    returnByValue: true)
      end
    end

    def history_navigate(delta:)
      history = command("Page.getNavigationHistory")
      index, entries = history.values_at("currentIndex", "entries")

      if entry = entries[index + delta]
        # Potential wait because of network event
        command("Page.navigateToHistoryEntry", wait: Mouse::CLICK_WAIT,
                                               slowmoable: true,
                                               entryId: entry["id"])
      end
    end

    def combine_url!(url_or_path)
      url = Addressable::URI.parse(url_or_path)
      nil_or_relative = url.nil? || url.relative?

      if nil_or_relative && !@browser.base_url
        raise "Set :base_url browser's option or use absolute url in `goto`, you passed: #{url_or_path}"
      end

      (nil_or_relative ? @browser.base_url.join(url.to_s) : url).to_s
    end

    def get_document_id
      @document_id = command("DOM.getDocument", depth: 0).dig("root", "nodeId")
    end
  end
end
