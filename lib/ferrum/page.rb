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
require "ferrum/page/navigation"
require "ferrum/page/screencast"
require "ferrum/page/screenshot"
require "ferrum/page/animation"
require "ferrum/page/tracing"
require "ferrum/page/stream"
require "ferrum/page/cookies"

module Ferrum
  #
  # Represents a single browser tab (a CDP target of type `page`). Owns the
  # tab's {Mouse}, {Keyboard}, {Network}, {Cookies}, {Headers}, {Downloads}
  # and {Accessibility} helpers, as well as its frame tree (see the included
  # {Page::Frames} module), and is the object that navigation, DOM search and
  # JavaScript evaluation methods are ultimately delegated to from {Browser}.
  #
  class Page
    NAVIGATION_WAIT = ENV.fetch("FERRUM_NAVIGATION_WAIT", 0.1).to_f
    WAIT_INTERVAL = 0.05
    WAIT_FOR_NAVIGATION_DEPRECATED = "wait_for_navigation will be removed in Ferrum 0.22. Use " \
                                     "await_navigation(watch: seconds) { ... } instead."
    WAIT_FOR_RELOAD_DEPRECATED = "wait_for_reload will be removed in Ferrum 0.22. Use await_navigation { ... } " \
                                 "around the code that reloads the page."

    extend Forwardable

    delegate %i[at_css at_xpath css xpath wait_css wait_css! wait_xpath wait_xpath! wait_for_selector
                url title html body doctype content=
                execution_id execution_id! evaluate evaluate_handle execute isolated_world
                add_script_tag add_style_tag] => :main_frame
    delegate %i[await_download await_download!] => :downloads
    delegate %i[base_url default_user_agent timeout timeout=] => :@options

    include Animation
    include Screencast
    include Screenshot
    include Frames
    include Navigation
    include Stream
    include Interceptable

    attr_reader :context_id, :target_id, :tracing

    # @api private
    attr_reader :idle

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

    # The cookies the page sees, `context.cookies` has all of the context's.
    #
    # @return [Page::Cookies]
    attr_reader :cookies

    # Downloads object.
    #
    # @return [Downloads]
    attr_reader :downloads

    # Bumped every time Chrome reports `DOM.documentUpdated` and after every
    # `DOM.getDocument`, both invalidate every node id handed out before them.
    #
    # @return [Integer]
    #
    # @api private
    attr_reader :document_version

    def initialize(client, context_id:, target_id:, proxy: nil)
      @javascript = true
      @client = client
      @context_id = context_id
      @target_id = target_id
      @options = client.options

      @frames = Concurrent::Map.new
      @main_frame = Frame.new(nil, self)
      @idle = Concurrency::Cell.set(true)
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
    # Closes the page's target and its underlying client connection.
    #
    # @return [nil]
    #
    # @example
    #   page.close # => true
    #
    def close
      client.notify("Target.closeTarget", targetId: @target_id)
      close_connection
      nil
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
    # @return [nil]
    #
    # @raise [TimeoutError]
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
      nil
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
    # @return [nil]
    #
    # @raise [TimeoutError]
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
    # Turns the page's own scripts on or off. Scripts skipped while they were off don't run when they are turned back
    # on, reload the page for that. JavaScript evaluated with Ferrum runs either way.
    #
    # @param [Boolean] enabled
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.javascript = false
    #   page.go_to("https://github.com/")
    #   page.javascript = true
    #   page.refresh
    #
    def javascript=(enabled)
      command("Emulation.setScriptExecutionDisabled", value: !enabled)
      @javascript = enabled
    end

    #
    # Whether the page's own scripts run, see {#javascript=}.
    #
    # @return [Boolean]
    #
    def javascript?
      @javascript
    end

    #
    # @deprecated Will be removed in Ferrum 0.22. Use `javascript = false`.
    #
    # @return [Hash]
    #
    # @raise [TimeoutError]
    def disable_javascript
      Utils::Deprecate.warn("disable_javascript will be removed in Ferrum 0.22. Use javascript = false instead.",
                            user_code: true)
      @javascript = false
      command("Emulation.setScriptExecutionDisabled", value: true)
    end

    #
    # The current position of the window.
    #
    # @return [(Integer, Integer)]
    #   The left, top coordinates of the window.
    #
    # @raise [TimeoutError]
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
    # @raise [TimeoutError]
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
    # @raise [TimeoutError]
    #
    # @example
    #   page.window_bounds = { left: 10, top: 20, width: 1024, height: 768, window_state: "normal" }
    #
    def window_bounds=(bounds)
      options = bounds.dup
      window_state = options.delete(:window_state)
      bounds = { windowState: window_state, **options }.compact

      command("Browser.setWindowBounds", windowId: window_id, bounds: bounds)
    end

    #
    # Current window bounds.
    #
    # @return [Hash{String => (Integer, String)}]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.window_bounds # => { "left": 0, "top": 1286, "width": 10, "height": 10, "windowState": "normal" }
    #
    def window_bounds
      command("Browser.getWindowBounds", windowId: window_id).fetch("bounds")
    end

    #
    # Current window id.
    #
    # @return [Integer]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.window_id # => 1
    #
    def window_id
      command("Browser.getWindowForTarget", targetId: target_id)["windowId"]
    end

    #
    # Runs the block until it returns a truthy value. The calls in the block
    # share the timeout.
    #
    # @param [Numeric, Deadline, nil] timeout
    #   How long to keep trying, the page's `timeout` by default.
    #
    # @param [Numeric] interval
    #   Seconds to sleep between the attempts.
    #
    # @yield The check to repeat.
    #
    # @return [Object, nil]
    #   What the block returned, `nil` if it didn't return a truthy value in time.
    #
    # @example
    #   page.wait_until { page.evaluate("window.ready") } # => true
    #
    def wait_until(timeout: nil, interval: WAIT_INTERVAL, &)
      Utils::Poll.call(timeout || self.timeout, interval, &)
    end

    #
    # Same as {#wait_until}, but raises if the block doesn't return a truthy
    # value in time.
    #
    # @param [Hash] options
    #   The options of {#wait_until}.
    #
    # @yield The check to repeat.
    #
    # @return [Object]
    #
    # @raise [TimeoutError]
    #   If the block doesn't return a truthy value in time.
    #
    def wait_until!(**options, &)
      wait_until(**options, &) || raise(TimeoutError)
    end

    #
    # Turns bypassing the page's Content Security Policy on or off. It applies from the next navigation.
    #
    # @param [Boolean] enabled
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.bypass_csp = true
    #   page.go_to("https://github.com/ruby-concurrency/concurrent-ruby/blob/master/docs-source/promises.in.md")
    #   page.add_script_tag(content: "window.__injected = 42")
    #   page.evaluate("window.__injected") # => 42
    #
    def bypass_csp=(enabled)
      command("Page.setBypassCSP", enabled: enabled)
    end

    #
    # @deprecated Will be removed in Ferrum 0.22. Use `bypass_csp = true`.
    #
    # @param [Boolean] enabled
    #
    # @return [Boolean]
    #
    # @raise [TimeoutError]
    #
    def bypass_csp(enabled: true)
      Utils::Deprecate.warn("bypass_csp(enabled:) will be removed in Ferrum 0.22. Use bypass_csp = true instead.",
                            user_code: true)
      self.bypass_csp = enabled
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
    # @raise [TimeoutError]
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
    # @return [nil]
    #
    # @raise [TimeoutError]
    #
    def remove_script_on_new_document(identifier)
      command("Page.removeScriptToEvaluateOnNewDocument", identifier: identifier)
      nil
    end

    #
    # Activates (focuses) the target for the given page.
    # When you have multiple tabs you work with, and you need to switch a given one.
    #
    # @return [nil]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.activate # => true
    #
    def activate
      command("Target.activateTarget", targetId: target_id)
      nil
    end

    #
    # Sends a CDP command to the browser. To wait for a navigation it starts,
    # wrap it in {#await_navigation}.
    #
    # @param [String] method
    #   The CDP method name, e.g. `"Page.navigate"`.
    #
    # @param [Boolean] slowmoable
    #   Whether to sleep for `Browser::Options#slowmo` seconds before sending
    #   the command.
    #
    # @param [Numeric, Deadline, nil] timeout
    #   Overrides the timeout this command's response is bound by. Defaults
    #   to the page's `timeout`. Callers with their own budget (e.g. `#pdf`/
    #   `#screenshot`) pass it explicitly.
    #
    # @return [Hash{String => Object}]
    #
    # @raise [TimeoutError]
    #
    # @raise [ArgumentError]
    #   When given the removed `wait:` or `async:`, which would otherwise be sent to the browser as parameters.
    #
    # @example
    #   page.command("Runtime.evaluate", expression: "1 + 1")
    #
    def command(method, slowmoable: false, timeout: nil, **params)
      raise ArgumentError, "wait: is removed, wrap #{method} in await_navigation instead" if params.key?(:wait)

      sleep(@options.slowmo) if slowmoable && @options.slowmo.positive?
      client.command(method, timeout: Deadline.wrap(timeout || self.timeout), **params)
    end

    # Subscribes to a CDP event, or to `:dialog`, `:request`, `:response`,
    # `:auth` (the latter three handled by {Interceptable}).
    #
    # @param [Symbol, String] name
    #
    # @return [Integer]
    #   The subscription id, used to unsubscribe via {#off}.
    def on(name, &)
      return super unless name == :dialog

      chain(:dialog).add(&)
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

      chain(:dialog).remove(id)
    end

    # Whether the page is configured to use a proxy.
    #
    # @return [Boolean]
    #
    # @api private
    def use_proxy?
      @proxy_host && @proxy_port
    end

    # Whether the page is configured to use a proxy that requires authentication.
    #
    # @return [Boolean]
    #
    # @api private
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
    # @raise [TimeoutError]
    #
    # @api private
    def document_node_id(async: false)
      result = if async
                 client.notify("DOM.getDocument", depth: 0)
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

      chain(:dialog)
    end

    def build_chain(name)
      return super unless name == :dialog

      Chain.new(client, "Page.javascriptDialogOpening",
                build: ->(params) { Dialog.new(self, params) },
                default: method(:accept_dialog), persistent: true)
    end

    def accept_dialog(dialog)
      warn "Dialog was shown but no `on(:dialog)` callback handled it, accepting it by default. " \
           "Please take a look at https://github.com/rubycdp/ferrum#dialogs"
      dialog.accept
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
                          type: :proxy) { |_request| nil }
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

    def proxy=(options)
      @proxy_host = options&.[](:host) || @options.proxy&.[](:host)
      @proxy_port = options&.[](:port) || @options.proxy&.[](:port)
      @proxy_user = options&.[](:user) || @options.proxy&.[](:user)
      @proxy_password = options&.[](:password) || @options.proxy&.[](:password)
    end
  end
end
