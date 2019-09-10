# frozen_string_literal: true

require "ferrum/mouse"
require "ferrum/keyboard"
require "ferrum/headers"
require "ferrum/cookies"
require "ferrum/page/dom"
require "ferrum/page/runtime"
require "ferrum/page/frame"
require "ferrum/page/net"
require "ferrum/page/screenshot"
require "ferrum/browser/client"
require "ferrum/network/error"
require "ferrum/network/request"
require "ferrum/network/response"
require "ferrum/network/intercepted_request"

# RemoteObjectId is from a JavaScript world, and corresponds to any JavaScript
# object, including JS wrappers for DOM nodes. There is a way to convert between
# node ids and remote object ids (DOM.requestNode and DOM.resolveNode).
#
# NodeId is used for inspection, when backend tracks the node and sends updates to
# the frontend. If you somehow got NodeId over protocol, backend should have
# pushed to the frontend all of it's ancestors up to the Document node via
# DOM.setChildNodes. After that, frontend is always kept up-to-date about anything
# happening to the node.
#
# BackendNodeId is just a unique identifier for a node. Obtaining it does not send
# any updates, for example, the node may be destroyed without any notification.
# This is a way to keep a reference to the Node, when you don't necessarily want
# to keep track of it. One example would be linking to the node from performance
# data (e.g. relayout root node). BackendNodeId may be either resolved to
# inspected node (DOM.pushNodesByBackendIdsToFrontend) or described in more
# details (DOM.describeNode).
module Ferrum
  class Page
    MODAL_WAIT = ENV.fetch("FERRUM_MODAL_WAIT", 0.05).to_f
    NEW_WINDOW_WAIT = ENV.fetch("FERRUM_NEW_WINDOW_WAIT", 0.3).to_f

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

    include DOM, Runtime, Frame, Net, Screenshot

    attr_accessor :referrer
    attr_reader :target_id, :status,
                :headers, :cookies, :response_headers,
                :mouse, :keyboard,
                :browser

    def initialize(target_id, browser, new_window = false)
      @target_id, @browser = target_id, browser
      @network_traffic = []
      @event = Event.new.tap(&:set)

      @frames = {}
      @waiting_frames ||= Set.new
      @frame_stack = []
      @accept_modal = []
      @modal_messages = []

      # Dirty hack because new window doesn't have events at all
      sleep(NEW_WINDOW_WAIT) if new_window

      @session_id = @browser.command("Target.attachToTarget", targetId: @target_id)["sessionId"]

      host = @browser.process.host
      port = @browser.process.port
      ws_url = "ws://#{host}:#{port}/devtools/page/#{@target_id}"
      @client = Browser::Client.new(browser, ws_url, 1000)

      @mouse, @keyboard = Mouse.new(self), Keyboard.new(self)
      @headers, @cookies = Headers.new(self), Cookies.new(self)

      subscribe
      prepare_page
    end

    def timeout
      @browser.timeout
    end

    def goto(url = nil)
      options = { url: combine_url!(url) }
      options.merge!(referrer: referrer) if referrer
      response = command("Page.navigate", wait: timeout, **options)
      # https://cs.chromium.org/chromium/src/net/base/net_error_list.h
      if %w[net::ERR_NAME_NOT_RESOLVED
            net::ERR_NAME_RESOLUTION_FAILED
            net::ERR_INTERNET_DISCONNECTED
            net::ERR_CONNECTION_TIMED_OUT].include?(response["errorText"])
        raise StatusError, options[:url]
      end
      response["frameId"]
    end

    def close
      @headers.clear
      @browser.command("Target.detachFromTarget", sessionId: @session_id)
      @browser.command("Target.closeTarget", targetId: @target_id)
      close_connection
    end

    def close_connection
      @client.close
    end

    def resize(width: nil, height: nil, fullscreen: false)
      result = @browser.command("Browser.getWindowForTarget", targetId: @target_id)
      @window_id, @bounds = result.values_at("windowId", "bounds")

      if fullscreen
        @browser.command("Browser.setWindowBounds", windowId: @window_id, bounds: { windowState: "fullscreen" })
      else
        @browser.command("Browser.setWindowBounds", windowId: @window_id, bounds: { windowState: "normal" })
        @browser.command("Browser.setWindowBounds", windowId: @window_id, bounds: { width: width, height: height, windowState: "normal" })
        command("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false)
      end
    end

    def refresh
      command("Page.reload", wait: timeout)
    end

    def network_traffic(type = nil)
      case type.to_s
      when "all"
        @network_traffic
      when "blocked"
        @network_traffic.select { |r| r.response.nil? } # when request blocked
      else
        @network_traffic.select { |r| r.response } # when request isn't blocked
      end
    end

    def clear_network_traffic
      @network_traffic = []
    end

    def back
      history_navigate(delta: -1)
    end

    def forward
      history_navigate(delta: 1)
    end

    def accept_confirm
      @accept_modal << true
    end

    def dismiss_confirm
      @accept_modal << false
    end

    def accept_prompt(modal_response)
      @accept_modal << true
      @modal_response = modal_response
    end

    def dismiss_prompt
      @accept_modal << false
    end

    def find_modal(options)
      start = Ferrum.monotonic_time
      timeout = options.fetch(:wait) { session_wait_time }
      expect_text = options[:text]
      expect_regexp = expect_text.is_a?(Regexp) ? expect_text : Regexp.escape(expect_text.to_s)
      not_found_msg = "Unable to find modal dialog"
      not_found_msg += " with #{expect_text}" if expect_text

      begin
        modal_text = @modal_messages.shift
        raise ModalNotFoundError if modal_text.nil? || (expect_text && !modal_text.match(expect_regexp))
      rescue ModalNotFoundError => e
        raise e, not_found_msg if Ferrum.timeout?(start, timeout)
        sleep(MODAL_WAIT)
        retry
      end

      modal_text
    end

    def reset_modals
      @accept_modal = []
      @modal_response = nil
      @modal_messages = []
    end

    def command(method, wait: 0, **params)
      iteration = @event.reset if wait > 0
      result = @client.command(method, params)
      if wait > 0
        @event.wait(wait)
        @event.wait(@browser.timeout) if iteration != @event.iteration
      end
      result
    end

    private

    def subscribe
      super

      if @browser.logger
        @client.on("Runtime.consoleAPICalled") do |params|
          params["args"].each { |r| @browser.logger.puts(r["value"]) }
        end
      end

      if @browser.js_errors
        @client.on("Runtime.exceptionThrown") do |params|
          # FIXME https://jvns.ca/blog/2015/11/27/why-rubys-timeout-is-dangerous-and-thread-dot-raise-is-terrifying/
          Thread.main.raise JavaScriptError.new(params.dig("exceptionDetails", "exception"))
        end
      end

      @client.on("Page.javascriptDialogOpening") do |params|
        accept_modal = @accept_modal.last
        if accept_modal == true || accept_modal == false
          @accept_modal.pop
          @modal_messages << params["message"]
          options = { accept: accept_modal }
          response = @modal_response || params["defaultPrompt"]
          options.merge!(promptText: response) if response
          command("Page.handleJavaScriptDialog", **options)
        else
          warn "Modal window has been opened, but you didn't wrap your code into (`accept_prompt` | `dismiss_prompt` | `accept_confirm` | `dismiss_confirm` | `accept_alert`), accepting by default"
          options = { accept: true }
          response = params["defaultPrompt"]
          options.merge!(promptText: response) if response
          command("Page.handleJavaScriptDialog", **options)
        end
      end

      @client.on("Page.windowOpen") do
        @browser.targets.refresh
      end

      @client.on("Page.navigatedWithinDocument") do
        @event.set if @waiting_frames.empty?
      end

      @client.on("Page.domContentEventFired") do |params|
        # `frameStoppedLoading` doesn't occur if status isn't success
        if @status != 200
          @event.set
          @document_id = get_document_id
        end
      end

      @client.on("Network.requestWillBeSent") do |params|
        if params["frameId"] == @frame_id
          # Possible types:
          # Document, Stylesheet, Image, Media, Font, Script, TextTrack, XHR,
          # Fetch, EventSource, WebSocket, Manifest, SignedExchange, Ping,
          # CSPViolationReport, Other
          if params["type"] == "Document"
            @event.reset
            @request_id = params["requestId"]
          end
        end

        id, time = params.values_at("requestId", "wallTime")
        params = params["request"].merge("id" => id, "time" => time)
        @network_traffic << Network::Request.new(params)
      end

      @client.on("Network.responseReceived") do |params|
        if params["requestId"] == @request_id
          @response_headers = params.dig("response", "headers")
          @status = params.dig("response", "status")
        end

        if request = @network_traffic.find { |r| r.id == params["requestId"] }
          params = params["response"].merge("id" => params["requestId"])
          request.response = Network::Response.new(params)
        end
      end

      @client.on("Network.loadingFinished") do |params|
        if request = @network_traffic.find { |r| r.id == params["requestId"] }
          # Sometimes we never get the Network.responseReceived event.
          # See https://crbug.com/883475
          #
          # Network.loadingFinished's encodedDataLength contains both body and headers
          # sizes received by wire. See https://crbug.com/764946
          if response = request.response
            response.body_size = params["encodedDataLength"] - response.headers_size
          end
        end
      end

      @client.on("Log.entryAdded") do |params|
        source = params.dig("entry", "source")
        level = params.dig("entry", "level")
        if source == "network" && level == "error"
          id = params.dig("entry", "networkRequestId")
          if request = @network_traffic.find { |r| r.id == id }
            request.error = Network::Error.new(params["entry"])
          end
        end
      end
    end

    def prepare_page
      command("Page.enable")
      command("DOM.enable")
      command("CSS.enable")
      command("Runtime.enable")
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
        @document_id = get_document_id
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
                                    contextId: execution_context_id,
                                    returnByValue: true)
      end
    end

    def history_navigate(delta:)
      history = command("Page.getNavigationHistory")
      index, entries = history.values_at("currentIndex", "entries")

      if entry = entries[index + delta]
        # Potential wait because of network event
        command("Page.navigateToHistoryEntry", wait: Mouse::CLICK_WAIT, entryId: entry["id"])
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
      command("DOM.getDocument", depth: 0).dig("root", "nodeId")
    end
  end
end
