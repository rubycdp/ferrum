# frozen_string_literal: true

require "forwardable"
require "pathname"
require "ferrum/mouse"
require "ferrum/keyboard"
require "ferrum/headers"
require "ferrum/cookies"
require "ferrum/dialog"
require "ferrum/network"
require "ferrum/console"
require "ferrum/accessibility"
require "ferrum/interceptable"
require "ferrum/downloads"
require "ferrum/page/frames"
require "ferrum/page/screencast"
require "ferrum/page/screenshot"
require "ferrum/page/animation"
require "ferrum/page/tracing"
require "ferrum/page/stream"

module Ferrum
  #
  # Represents a single browser tab (a CDP target of type `page`). Owns the
  # tab's {Mouse}, {Keyboard}, {Network}, {Cookies}, {Headers}, {Downloads}
  # and {Accessibility} helpers, as well as its frame tree (see the included
  # {Page::Frames} module), and is the object that navigation, DOM search and
  # JavaScript evaluation methods are ultimately delegated to from {Browser}.
  #
  class Page
    GOTO_WAIT = ENV.fetch("FERRUM_GOTO_WAIT", 0.1).to_f

    extend Forwardable

    delegate %i[at_css at_xpath css xpath wait_for_selector
                current_url current_title url title body doctype content=
                execution_id execution_id! evaluate evaluate_handle execute
                evaluate_on evaluate_async evaluate_func isolated_world
                add_script_tag add_style_tag] => :main_frame
    delegate %i[base_url default_user_agent timeout timeout=] => :@options

    include Animation
    include Screencast
    include Screenshot
    include Frames
    include Stream
    include Interceptable

    attr_accessor :referrer
    attr_reader :context_id, :target_id, :event, :tracing

    # Client connection.
    #
    # @return [Client]
    attr_reader :client

    # Mouse object.
    #
    # @return [Mouse]
    attr_reader :mouse

    # Keyboard object.
    #
    # @return [Keyboard]
    attr_reader :keyboard

    # Network object.
    #
    # @return [Network]
    attr_reader :network

    # Console messages.
    #
    # @return [Console]
    attr_reader :console

    # Accessibility object.
    #
    # @return [Accessibility]
    attr_reader :accessibility

    # Headers object.
    #
    # @return [Headers]
    attr_reader :headers

    # Cookie store.
    #
    # @return [Cookies]
    attr_reader :cookies

    # Downloads object.
    #
    # @return [Downloads]
    attr_reader :downloads

    # Bumped every time Chrome reports `DOM.documentUpdated` and after every
    # `DOM.getDocument`, both invalidate every node id handed out before them.
    #
    # @return [Integer]
    attr_reader :document_version

    def initialize(client, context_id:, target_id:, proxy: nil)
      @client = client
      @context_id = context_id
      @target_id = target_id
      @options = client.options

      @frames = Concurrent::Map.new
      @main_frame = Frame.new(nil, self)
      @event = Utils::Event.new.tap(&:set)
      @document_version = 0
      self.proxy = proxy

      @mouse = Mouse.new(self)
      @keyboard = Keyboard.new(self)
      @headers = Headers.new(self)
      @cookies = Cookies.new(self)
      @network = Network.new(self)
      @console = Console.new(self)
      @accessibility = Accessibility.new(self)
      @tracing = Tracing.new(self)
      @downloads = Downloads.new(self)

      subscribe
      prepare_page
    end

    #
    # Navigates the page to a URL.
    #
    # @param [String, nil] url
    #   The URL to navigate to. The url should include scheme unless you set
    #   `{Browser#base_url = url}` when configuring.
    #
    # @example
    #   page.go_to("https://github.com/")
    #
    def go_to(url = nil)
      options = { url: combine_url!(url) }
      options.merge!(referrer: referrer) if referrer
      response = command("Page.navigate", wait: GOTO_WAIT, **options)
      error_text = response["errorText"] # https://cs.chromium.org/chromium/src/net/base/net_error_list.h
      if error_text && error_text != "net::ERR_ABORTED" # Request aborted due to user action or download
        raise StatusError.new(options[:url], "Request to #{options[:url]} failed (#{error_text})")
      end

      response["frameId"]
    rescue TimeoutError
      if @options.pending_connection_errors
        pendings = network.traffic.select(&:pending?).map(&:url).compact
        raise PendingConnectionsError.new(options[:url], Array(pendings))
      end
    end
    alias goto go_to
    alias go go_to

    #
    # Closes the page's target and its underlying client connection.
    #
    # @return [Boolean]
    #
    # @example
    #   page.close # => true
    #
    def close
      @headers.clear
      client.command("Target.closeTarget", async: true, targetId: @target_id)
      close_connection

      true
    end

    #
    # Closes the underlying client connection only, without closing the
    # target itself. Useful when you want to detach from a page without
    # ending the browser tab it represents.
    #
    def close_connection
      client&.close
    end

    #
    # Overrides device screen dimensions and emulates viewport according to parameters
    #
    # Read more [here](https://chromedevtools.github.io/devtools-protocol/tot/Emulation/#method-setDeviceMetricsOverride).
    #
    # @param [Integer] width width value in pixels. 0 disables the override
    #
    # @param [Integer] height height value in pixels. 0 disables the override
    #
    # @param [Float] scale_factor device scale factor value. 0 disables the override
    #
    # @param [Boolean, nil] mobile `true` emulates a mobile device with touch, `false` a desktop without touch, `nil`
    #   a desktop and leaves touch emulation as is. Turning touch off resets hover and pointer to the detected input
    #   devices, which undoes `--blink-settings` overrides until the next navigation
    #
    def set_viewport(width: 0, height: 0, scale_factor: 0, mobile: nil)
      command("Emulation.setTouchEmulationEnabled", enabled: mobile, maxTouchPoints: 1) unless mobile.nil?

      command(
        "Emulation.setDeviceMetricsOverride",
        slowmoable: true,
        width: width,
        height: height,
        deviceScaleFactor: scale_factor,
        mobile: mobile || false
      )
    end

    #
    # Resizes the window and emulates the viewport accordingly, optionally
    # switching to fullscreen.
    #
    # @param [Integer, nil] width width value in pixels.
    #
    # @param [Integer, nil] height height value in pixels.
    #
    # @param [Boolean] fullscreen whether to put the window into fullscreen
    #   mode. When `true`, `width` and `height` are read from
    #   {#document_size} instead of the given arguments.
    #
    # @return [Hash{String => Object}]
    #
    # @example
    #   page.resize(width: 1024, height: 768)
    #
    # @example
    #   page.resize(fullscreen: true)
    #
    def resize(width: nil, height: nil, fullscreen: false)
      if fullscreen
        width, height = document_size
        self.window_bounds = { window_state: "fullscreen" }
      else
        self.window_bounds = { window_state: "normal" }
        self.window_bounds = { width: width, height: height }
      end

      set_viewport(width: width, height: height)
    end

    #
    # Disables JavaScript execution from the HTML source for the page.
    #
    # This doesn't prevent users evaluate JavaScript with Ferrum.
    #
    def disable_javascript
      command("Emulation.setScriptExecutionDisabled", value: true)
    end

    #
    # The current position of the window.
    #
    # @return [(Integer, Integer)]
    #   The left, top coordinates of the window.
    #
    # @example
    #   page.position # => [10, 20]
    #
    def position
      window_bounds.values_at("left", "top")
    end

    #
    # Sets the position of the window.
    #
    # @param [Hash{Symbol => Object}] options
    #
    # @option options [Integer] :left
    #   The number of pixels from the left-hand side of the screen.
    #
    # @option options [Integer] :top
    #   The number of pixels from the top of the screen.
    #
    # @example
    #   page.position = { left: 10, top: 20 }
    #
    def position=(options)
      self.window_bounds = { left: options[:left], top: options[:top] }
    end

    # Sets the position of the window.
    #
    # @param [Hash{Symbol => Object}] bounds
    #
    # @option options [Integer] :left
    #   The number of pixels from the left-hand side of the screen.
    #
    # @option options [Integer] :top
    #   The number of pixels from the top of the screen.
    #
    # @option options [Integer] :width
    #   The window width in pixels.
    #
    # @option options [Integer] :height
    #   The window height in pixels.
    #
    # @option options [String] :window_state
    #   The window state. Default to normal. Allowed Values: normal, minimized, maximized, fullscreen
    #
    # @example
    #   page.window_bounds = { left: 10, top: 20, width: 1024, height: 768, window_state: "normal" }
    #
    def window_bounds=(bounds)
      options = bounds.dup
      window_state = options.delete(:window_state)
      bounds = { windowState: window_state, **options }.compact

      client.command("Browser.setWindowBounds", windowId: window_id, bounds: bounds)
    end

    #
    # Current window bounds.
    #
    # @return [Hash{String => (Integer, String)}]
    #
    # @example
    #   page.window_bounds # => { "left": 0, "top": 1286, "width": 10, "height": 10, "windowState": "normal" }
    #
    def window_bounds
      client.command("Browser.getWindowBounds", windowId: window_id).fetch("bounds")
    end

    #
    # Current window id.
    #
    # @return [Integer]
    #
    # @example
    #   page.window_id # => 1
    #
    def window_id
      client.command("Browser.getWindowForTarget", targetId: target_id)["windowId"]
    end

    #
    # Reloads the current page.
    #
    # @example
    #   page.go_to("https://github.com/")
    #   page.refresh
    #
    def refresh
      command("Page.reload", wait: timeout, slowmoable: true)
    end
    alias reload refresh

    #
    # Stop all navigations and loading pending resources on the page.
    #
    # @example
    #   page.go_to("https://github.com/")
    #   page.stop
    #
    def stop
      command("Page.stopLoading", slowmoable: true)
    end

    #
    # Navigates to the previous URL in the history.
    #
    # @example
    #   page.go_to("https://github.com/")
    #   page.at_xpath("//a").click
    #   page.back
    #
    def back
      history_navigate(delta: -1)
    end

    #
    # Navigates to the next URL in the history.
    #
    # @example
    #   page.go_to("https://github.com/")
    #   page.at_xpath("//a").click
    #   page.back
    #   page.forward
    #
    def forward
      history_navigate(delta: 1)
    end

    #
    # Blocks until the page reloads or the timeout is reached.
    #
    # @param [Numeric] timeout
    #   Maximum time in seconds to wait for a reload event.
    #
    # @example
    #   page.wait_for_reload
    #
    def wait_for_reload(timeout = 1)
      @event.reset if @event.set?
      @event.wait(timeout)
      @event.set
    end

    #
    # Runs the block and, if it starts a navigation of the main frame within
    # `wait` seconds, waits for that navigation to finish, e.g. after a click
    # on a link made from JavaScript.
    #
    # @param [Numeric] wait
    #   How many seconds to watch for a navigation after the block returns.
    #
    # @yield The code that may start a navigation.
    #
    # @return [Boolean]
    #   `false` when a navigation started but didn't finish within the page's
    #   `timeout`.
    #
    # @example
    #   page.wait_for_navigation { page.at_css("a").evaluate("this.click()") } # => true
    #
    def wait_for_navigation(wait = Mouse::CLICK_WAIT)
      iteration = @event.reset
      yield
      @event.wait(wait)
      iteration == @event.iteration || @event.wait(timeout)
    end

    #
    # Waits for a navigation the block starts or raises {Ferrum::TimeoutError}.
    # Accepts the same arguments as {#wait_for_navigation}.
    #
    # @raise [Ferrum::TimeoutError]
    #
    def wait_for_navigation!(...)
      raise TimeoutError unless wait_for_navigation(...)
    end

    #
    # Enables/disables CSP bypass.
    #
    # @param [Boolean] enabled
    #
    # @return [Boolean]
    #
    # @example
    #   page.bypass_csp # => true
    #   page.go_to("https://github.com/ruby-concurrency/concurrent-ruby/blob/master/docs-source/promises.in.md")
    #   page.refresh
    #   page.add_script_tag(content: "window.__injected = 42")
    #   page.evaluate("window.__injected") # => 42
    #
    def bypass_csp(enabled: true)
      command("Page.setBypassCSP", enabled: enabled)
      enabled
    end

    #
    # Adds JavaScript to run in every new document of this page and its in-process frames, before the document's own
    # scripts. For every page and iframe of the browser, see {Browser::Options#add_extension}.
    #
    # @param [String] source
    #
    # @param [String, nil] world_name
    #   Runs the script in an isolated world with this name instead of the page's main world.
    #
    # @param [Boolean] run_immediately
    #   Runs the script in the current document as well.
    #
    # @return [String]
    #   The script identifier, for {#remove_script_on_new_document}.
    #
    # @example
    #   page.evaluate_on_new_document <<~JS
    #     Object.defineProperty(navigator, "languages", {
    #       get: function() { return ["tlh"]; }
    #     });
    #   JS
    #
    def evaluate_on_new_document(source, world_name: nil, run_immediately: false)
      params = { source: source, worldName: world_name, runImmediately: run_immediately }.compact
      command("Page.addScriptToEvaluateOnNewDocument", **params)["identifier"]
    end

    #
    # Stops running a script added with {#evaluate_on_new_document} in new documents.
    #
    # @param [String] identifier
    #
    # @return [true]
    #
    def remove_script_on_new_document(identifier)
      command("Page.removeScriptToEvaluateOnNewDocument", identifier: identifier)
      true
    end

    #
    # Activates (focuses) the target for the given page.
    # When you have multiple tabs you work with, and you need to switch a given one.
    #
    # @return [Boolean]
    #
    # @example
    #   page.activate # => true
    #
    def activate
      command("Target.activateTarget", targetId: target_id)
      true
    end

    #
    # Sends a CDP command to the browser and optionally waits for network
    # activity on the main frame to settle before returning.
    #
    # @param [String] method
    #   The CDP method name, e.g. `"Page.navigate"`.
    #
    # @param [Numeric] wait
    #   How many seconds to wait for a network event on the main frame after
    #   the command is sent. `0` disables waiting.
    #
    # @param [Boolean] slowmoable
    #   Whether to sleep for `Browser::Options#slowmo` seconds before sending
    #   the command.
    #
    # @param [Numeric, nil] timeout
    #   Overrides the timeout this command's response is bound by. Defaults
    #   to the page's `timeout`. Callers with their own budget (e.g. `#pdf`/
    #   `#screenshot`) pass it explicitly.
    #
    # @return [Hash{String => Object}]
    #
    # @example
    #   page.command("Page.navigate", url: "https://github.com/")
    #
    def command(method, wait: 0, slowmoable: false, timeout: nil, **params)
      if wait.positive?
        result = nil
        wait_for_navigation!(wait) { result = command(method, slowmoable:, timeout:, **params) }
        return result
      end

      sleep(@options.slowmo) if slowmoable && @options.slowmo.positive?
      client.command(method, timeout: timeout || self.timeout, **params)
    end

    # Subscribes to a CDP event, or to `:dialog`, `:request`, `:response`,
    # `:auth` (the latter three handled by {Interceptable}).
    #
    # @param [Symbol, String] name
    #
    # @return [Integer]
    #   The subscription id, used to unsubscribe via {#off}.
    def on(name, &block)
      return super unless name == :dialog

      client.on("Page.javascriptDialogOpening") do |params, index, total|
        dialog = Dialog.new(self, params)
        block.call(dialog, index, total)
      end
    end

    # Unsubscribes a listener previously registered via {#on}.
    #
    # @param [Symbol, String] name
    #
    # @param [Integer] id
    #   The subscription id returned by {#on}.
    #
    # @return [void]
    def off(name, id)
      return super unless name == :dialog

      client.off("Page.javascriptDialogOpening", id)
    end

    # Whether the page is configured to use a proxy.
    #
    # @return [Boolean]
    def use_proxy?
      @proxy_host && @proxy_port
    end

    # Whether the page is configured to use a proxy that requires authentication.
    #
    # @return [Boolean]
    def use_authorized_proxy?
      use_proxy? && @proxy_user && @proxy_password
    end

    #
    # Returns the node id of the document's root element.
    #
    # @param [Boolean] async
    #   Whether to send the command without waiting for a response.
    #
    # @return [Integer, Boolean]
    #   The root node id, or `true` when sent asynchronously.
    #
    def document_node_id(async: false)
      result = if async
                 client.command("DOM.getDocument", async: true, depth: 0)
               else
                 command("DOM.getDocument", depth: 0).dig("root", "nodeId")
               end
      @document_version += 1
      result
    end

    private

    def subscribe
      frames_subscribe
      network.subscribe
      console.subscribe
      downloads.subscribe

      on("DOM.documentUpdated") { @document_version += 1 }

      if @options.js_errors
        on("Runtime.exceptionThrown") do |params|
          # FIXME: https://jvns.ca/blog/2015/11/27/why-rubys-timeout-is-dangerous-and-thread-dot-raise-is-terrifying/
          Thread.main.raise JavaScriptError, params["exceptionDetails"]
        end
      end

      on(:dialog) do |dialog, _index, total|
        if total == 1
          warn "Dialog was shown but you didn't provide `on(:dialog)` callback, accepting it by default. " \
               "Please take a look at https://github.com/rubycdp/ferrum#dialogs"
          dialog.accept
        end
      end
    end

    def prepare_page
      command("Page.enable")
      command("Page.setLifecycleEventsEnabled", enabled: true)
      command("Runtime.enable")
      command("DOM.enable", includeWhitespace: "all")
      command("CSS.enable")
      command("Log.enable")
      command("Network.enable")

      if use_authorized_proxy?
        network.authorize(user: @proxy_user,
                          password: @proxy_password,
                          type: :proxy) do |request, _index, total|
          request.continue if total == 1
        end
      end

      downloads.set_behavior(save_path: @options.save_path) if @options.save_path

      response = command("Page.getNavigationHistory")
      transition_type = response.dig("entries", 0, "transitionType")
      return if transition_type == "auto_toplevel"

      # If we create page by clicking links, submitting forms and so on it
      # opens a new window for which `frameStoppedLoading` event never
      # occurs and thus search for nodes cannot be completed. Here we check
      # the history and if the transitionType for example `link` then
      # content is already loaded, and we can try to get the document.
      document_node_id
    end

    def history_navigate(delta:)
      history = command("Page.getNavigationHistory")
      index, entries = history.values_at("currentIndex", "entries")
      entry = entries[index + delta]

      return unless entry

      # Potential wait because of network event
      command("Page.navigateToHistoryEntry",
              wait: Mouse::CLICK_WAIT,
              slowmoable: true,
              entryId: entry["id"])
    end

    def combine_url!(url_or_path)
      url = Addressable::URI.parse(url_or_path)
      nil_or_relative = url.nil? || url.relative?

      if nil_or_relative && !@options.base_url
        raise "Set :base_url browser's option or use absolute url in `go_to`, you passed: #{url_or_path}"
      end

      (nil_or_relative ? @options.base_url.join(url.to_s) : url).to_s
    end

    def proxy=(options)
      @proxy_host = options&.[](:host) || @options.proxy&.[](:host)
      @proxy_port = options&.[](:port) || @options.proxy&.[](:port)
      @proxy_user = options&.[](:user) || @options.proxy&.[](:user)
      @proxy_password = options&.[](:password) || @options.proxy&.[](:password)
    end
  end
end
