# frozen_string_literal: true

module Ferrum
  #
  # Represents a DOM node (an element or a text node) found on a {Page} or
  # within a {Frame}. Provides methods to inspect it (`text`, `property`,
  # `attribute`), interact with it (`click`, `focus`, `type`, `select`) and
  # search within it (`at_css`, `at_xpath`, `css`, `xpath`).
  #
  # @note Node identity is tied to the target it was found on; a `Node`
  #   fetched before a navigation cannot be used afterwards.
  #
  class Node
    MOVING_WAIT_DELAY = ENV.fetch("FERRUM_NODE_MOVING_WAIT", 0.01).to_f
    MOVING_WAIT_ATTEMPTS = ENV.fetch("FERRUM_NODE_MOVING_ATTEMPTS", 50).to_i
    MOVING_CHECK_DELAY = ENV.fetch("FERRUM_NODE_MOVING_CHECK", 0.05).to_f
    WAIT_FOR_STOP_MOVING_DEPRECATED = "wait_for_stop_moving will be removed in Ferrum 0.22. Use wait_still instead."

    # @return [Page] the page the node belongs to.
    attr_reader :page

    # @return [String] the id of the page's target.
    attr_reader :target_id

    # @return [Integer] Chrome's id of the node, stable for the node's lifetime.
    attr_reader :backend_node_id

    # @return [Integer] the DOM `nodeType`, e.g. `1` for an element, `3` for a text node.
    attr_reader :node_type

    # @return [String, nil] the id of the frame an `iframe` or `frame` element contains, `nil` for other nodes.
    attr_reader :frame_id

    #
    # @param [Frame, IsolatedWorld] frame
    #   The runtime the node was returned from.
    #
    # @param [Hash{String => Object}] properties
    #   The node's properties from Chrome's deep serialization.
    #
    def initialize(frame, properties)
      @runtime = frame
      @page = frame.page
      @target_id = @page.target_id
      @backend_node_id = properties["backendNodeId"]
      @node_type = properties["nodeType"]
      @tag_name = properties["localName"]&.downcase
      @frame_id = properties["frameId"]
      @document_version = @page.document_version
    end

    #
    # Chrome's description of the node from `DOM.describeNode`, fetched on
    # first use.
    #
    # @return [Hash{String => Object}]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.at_css("a").description["nodeName"] # => "A"
    #
    def description
      @description ||= page.command("DOM.describeNode", backendNodeId: backend_node_id)["node"]
    end

    #
    # The lowercased tag name of an element, or the node name of any other
    # node, e.g. `"#text"`.
    #
    # @return [String]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.at_css("#nav").tag_name # => "div"
    #
    def tag_name
      @tag_name ||= description["nodeName"].downcase
    end

    # Frontend node id is resolved lazily, on first actual need (focus, click, scroll, etc.)
    # We can try to subscribe to `DOM.childNodeRemoved` and `DOM.childNodeInserted` in the future
    # to keep track of nodes.
    def node_id
      return @node_id if @node_id && @document_version == page.document_version

      document_version = page.document_version
      @node_id = begin
        id = page.command("DOM.pushNodesByBackendIdsToFrontend",
                          backendNodeIds: [backend_node_id])["nodeIds"].first
        raise NodeNotFoundError, { "message" => "node is not trackable" } if id.zero?

        id
      rescue BrowserError => e
        raise unless e.message == "Document needs to be requested first"

        raise NodeNotFoundError, { "message" => "node is not trackable, the page is still loading a new document" }
      end
      @document_version = document_version
      @node_id
    end

    # Whether this is an element node, as opposed to e.g. a text node.
    #
    # @return [Boolean]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.at_css("a").node? # => true
    #   page.xpath("//a/text()").first.node? # => false
    #
    def node?
      node_type == 1 # nodeType: 3, nodeName: "#text" e.g.
    end

    #
    # The {Frame} this node belongs to. Keep using finder methods (`at_css`,
    # `at_xpath`, etc.) on it to search within that frame, e.g. inside an
    # `iframe`.
    #
    # @return [Frame, nil]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   frame = page.at_xpath("//iframe").frame # => Frame
    #   frame.at_css("//a[text() = 'Log in']") # => Node
    #
    def frame
      page.frame_by(id: frame_id)
    end

    #
    # Focuses the node.
    #
    # @return [self]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   input = page.at_css("input[name='q']")
    #   input.focus
    #
    def focus
      tap { page.command("DOM.focus", slowmoable: true, nodeId: node_id) }
    end

    # Whether the node can receive focus. Attempts to {#focus} the node to
    # find out, and leaves it focused when it can.
    #
    # @return [Boolean]
    #
    # @raise [TimeoutError]
    def focusable?
      focus
      true
    rescue BrowserError => e
      e.message == "Element is not focusable" ? false : raise
    end

    #
    # Polls the node's position until two snapshots taken `interval` seconds
    # apart match, see {#moving?}.
    #
    # @param [Numeric, Deadline, nil] timeout
    #   How long to keep trying, the page's `timeout` by default.
    #
    # @param [Numeric] interval
    #   Seconds between the two snapshots of an attempt.
    #
    # @return [Array<Array<Float>>, nil]
    #   The content quads of the node once it stands still, each one as the
    #   eight coordinates of its four corners. `nil` if it keeps moving.
    #
    # @raise [CoordinatesNotFoundError]
    #   If the node isn't visible.
    #
    # @example
    #   page.at_css("#modal").wait_still
    #   # => [[50.2, 390.9, 203.2, 390.9, 203.2, 411.9, 50.2, 411.9]]
    #
    def wait_still(timeout: nil, interval: MOVING_WAIT_DELAY)
      Utils::Poll.call(timeout || page.timeout, 0) do
        previous, current = content_quads_with(delay: interval)
        current if previous == current
      end
    end

    #
    # Same as {#wait_still}, but raises if the node keeps moving.
    #
    # @param [Hash] options
    #   The options of {#wait_still}.
    #
    # @return [Array<Array<Float>>]
    #
    # @raise [TimeoutError]
    #   If the node keeps moving.
    #
    def wait_still!(**options)
      wait_still(**options) || raise(TimeoutError)
    end

    #
    # Waits until the node's position stops changing, retrying up to
    # `attempts` times.
    #
    # @deprecated Will be removed in Ferrum 0.22. Use {#wait_still}.
    #
    # @param [Float] delay
    #
    # @param [Integer] attempts
    #
    # @return [Array<Array<Float>>]
    #
    # @raise [NodeMovingError]
    #
    def wait_for_stop_moving(delay: MOVING_WAIT_DELAY, attempts: MOVING_WAIT_ATTEMPTS)
      Utils::Deprecate.warn(WAIT_FOR_STOP_MOVING_DEPRECATED, user_code: true)
      settled_quads(delay: delay, attempts: attempts)
    end

    # Checks whether the node's position is changing, by comparing two
    # content-quad snapshots taken `delay` seconds apart. The default is a few
    # frames, a shorter one can miss a node that moves slowly.
    #
    # @param [Float] delay
    #   Seconds to wait between the two position checks.
    #
    # @return [Boolean]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.at_css(".animated").moving? # => true
    #   page.at_css("#nav").moving? # => false
    #
    def moving?(delay: MOVING_CHECK_DELAY)
      previous, current = content_quads_with(delay: delay)
      previous != current
    end

    #
    # Removes focus from the node.
    #
    # @return [self]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.at_css("input[name='q']").focus.blur
    #
    def blur
      tap { evaluate("this.blur()") }
    end

    #
    # Sends keystrokes to the currently focused element via the page's
    # keyboard. Typically chained after {#focus} or `click`.
    #
    # @param [Array<String, Symbol, (Symbol, String)>] keys
    #   The keys to type, e.g. `"Input"`, `[:Shift, "s"], "tring"`.
    #
    # @param [Numeric, Deadline, nil] timeout
    #   How long typing all the keys may take together, the page timeout by default.
    #
    # @return [self]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   input.focus.type("Input")
    #   input.focus.type(long_text, timeout: 30)
    #
    def type(*keys, timeout: nil)
      tap { page.keyboard.type(*keys, timeout: timeout) }
    end

    #
    # Clicks the node at its center, or at an offset from it, by moving the
    # mouse there first. Waits for the node to stop moving, see
    # {#wait_still}.
    #
    # @param [:left, :right, :double] mode
    #   Which click to make, `:double` is a double click with the left button.
    #
    # @param [Array<Symbol>] keys
    #   Modifier keys to hold while clicking: `:alt`, `:ctrl` (or `:control`),
    #   `:meta` (or `:command`) and `:shift`.
    #
    # @param [Hash{Symbol => Object}] offset
    #   Where to click instead of the center, needs both `:x` and `:y`.
    #
    # @option offset [Integer] :x
    #
    # @option offset [Integer] :y
    #
    # @option offset [:top, :center] :position (:top)
    #   What `:x` and `:y` are measured from: the node's top-left corner or its
    #   center.
    #
    # @param [Float] delay
    #   Delay between mouse down and mouse up events.
    #
    # @param [Numeric, false] navigation_wait
    #   Seconds to watch for a navigation started by a left click, then wait for
    #   it to load. Ignored for `:right` and `:double`, which never wait. `false`
    #   returns as soon as the click is dispatched.
    #
    # @param [Numeric, nil] wait
    #   Deprecated, renamed to `navigation_wait`.
    #
    # @param [Numeric, Deadline, nil] timeout
    #   How long finding the node's position, the click and the page load it starts may take together, the page
    #   timeout by default.
    #
    # @return [self]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.at_css("a").click
    #   page.at_css("a").click(timeout: 30)
    #   page.at_css("a").click(navigation_wait: false)
    #   page.at_css("a").click(mode: :right)
    #   page.at_css("a").click(keys: [:ctrl, :shift])
    #   page.at_css("canvas").click(offset: { x: 10, y: 20 })
    #   page.at_css("canvas").click(offset: { x: 10, y: 20, position: :center })
    #
    def click(mode: :left, keys: [], offset: {}, delay: 0, navigation_wait: Page::NAVIGATION_WAIT, wait: nil, # rubocop:disable Metrics/ParameterLists
              timeout: nil)
      navigation_wait = Utils::Deprecate.renamed_keyword(:wait, :navigation_wait, wait, navigation_wait)
      deadline = Deadline.wrap(timeout || page.timeout)
      Deadline.within(deadline) do
        x, y = find_position(**offset)
        modifiers = page.keyboard.modifiers(keys)

        # `:right` and `:double` pass `navigation_wait: false` to preserve the historical
        # no-network-wait default of `Mouse#up` and `Mouse#down`
        case mode
        when :right
          page.mouse.click(x:, y:, modifiers:, delay:, button: :right, navigation_wait: false, timeout: deadline)
        when :double
          page.mouse.click(x:, y:, modifiers:, delay:, count: 2, navigation_wait: false, timeout: deadline)
        when :left
          page.mouse.click(x:, y:, modifiers:, delay:, navigation_wait:, timeout: deadline)
        end
      end

      self
    end

    # Not currently implemented.
    #
    # @raise [Ferrum::NotImplementedError] always
    #
    # @raise [TimeoutError]
    def hover
      raise Ferrum::NotImplementedError
    end

    #
    # Scrolls the node into view if it is not already visible.
    #
    # @return [self]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.at_css("#footer").scroll
    #
    def scroll
      tap { page.command("DOM.scrollIntoViewIfNeeded", nodeId: node_id) }
    end

    #
    # @deprecated Will be removed in Ferrum 0.22. Use {#scroll}.
    #
    # @return [self]
    #
    # @raise [TimeoutError]
    #
    def scroll_into_view
      Utils::Deprecate.warn("scroll_into_view will be removed in Ferrum 0.22. Use scroll instead.", user_code: true)
      scroll
    end

    # Whether the node's bounding rect is fully within the viewport (or,
    # when `of:` is given, within that scoping element's bounds).
    #
    # @param [Node, nil] of
    #   An element to use as the visible bounds instead of the window.
    #
    # @return [Boolean]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.at_css("#footer").in_viewport? # => false
    #   page.at_css("#footer").scroll.in_viewport? # => true
    #   page.at_css("#row").in_viewport?(of: page.at_css("#table")) # => true
    #
    def in_viewport?(of: nil)
      evaluate(<<~JS, of)
        function(scope) {
          const rect = this.getBoundingClientRect();
          const [height, width] = scope
            ? [scope.offsetHeight, scope.offsetWidth]
            : [window.innerHeight, window.innerWidth];
          return rect.top >= 0 &&
           rect.left >= 0 &&
           rect.bottom <= height &&
           rect.right <= width;
        }
      JS
    end

    #
    # Sets files on a file input node.
    #
    # @param [String, Array<String>] value
    #   Path or paths to the file(s) to upload.
    #
    # @return [Hash{String => Object}]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.at_css("input[type=file]").select_file("/path/to/file.png")
    #
    def select_file(value)
      page.command(
        "DOM.setFileInputFiles",
        slowmoable: true,
        backendNodeId: backend_node_id,
        files: Array(value)
      )
    end

    #
    # Finds a node by xpath, scoped to search within this node. Runs
    # `document.evaluate` within this node.
    #
    # @param [String] selector
    #
    # @return [Node, nil]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.at_xpath("//nav").at_xpath(".//a") # => Node
    #
    def at_xpath(selector)
      @runtime.at_xpath(selector, within: self)
    end

    #
    # Finds a node by CSS selector, scoped to search within this node. Runs
    # `querySelector` within this node.
    #
    # @param [String] selector
    #
    # @return [Node, nil]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.at_css("form").at_css("input[name='q']") # => Node
    #
    def at_css(selector)
      @runtime.at_css(selector, within: self)
    end

    #
    # Finds nodes by xpath, scoped to search within this node. Runs
    # `document.evaluate` within this node.
    #
    # @param [String] selector
    #
    # @return [Array<Node>]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.at_css("ul").xpath(".//li") # => [Node]
    #
    def xpath(selector)
      @runtime.xpath(selector, within: self)
    end

    #
    # Finds nodes by CSS selector, scoped to search within this node. Runs
    # `querySelectorAll` within this node.
    #
    # @param [String] selector
    #
    # @return [Array<Node>]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.at_css("ul").css("li") # => [Node]
    #
    def css(selector)
      @runtime.css(selector, within: self)
    end

    #
    # The node's text content, i.e. `textContent`.
    #
    # @return [String]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.at_css("a > h3").text # => "rubycdp/ferrum: Ruby Chrome/Chromium driver - GitHub"
    #
    def text
      evaluate("this.textContent")
    end

    #
    # The node's rendered text, i.e. `innerText`. Unlike {#text}, it follows
    # the layout: text hidden by CSS is left out and line breaks are kept.
    #
    # @return [String]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   # <p>Hello <span style="display: none">hidden</span>world</p>
    #   page.at_css("p").text # => "Hello hiddenworld"
    #   page.at_css("p").inner_text # => "Hello world"
    #
    def inner_text
      evaluate("this.innerText")
    end

    #
    # The node's `value` property. Useful for form elements such as `input`,
    # `select` and `textarea`.
    #
    # @return [Object]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.at_css("input[name='q']").value # => "ferrum"
    #
    def value
      evaluate("this.value")
    end

    #
    # Returns the given JavaScript property of the node.
    #
    # @param [String] name
    #
    # @return [Object]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.at_css("input").property("value") # => "Foo"
    #
    def property(name)
      evaluate("this[name]", name: name)
    end

    #
    # @deprecated Will be removed in Ferrum 0.22. Use {#property}.
    #
    # @param [String] name
    #
    # @return [Object]
    #
    # @raise [TimeoutError]
    #
    def [](name)
      Utils::Deprecate.warn("node[name] will be removed in Ferrum 0.22. Use property(name) instead.", user_code: true)
      property(name)
    end

    #
    # Returns the value of the given HTML attribute, i.e.
    # `getAttribute(name)`. Unlike {#property}, it reads the attribute as
    # defined in markup rather than the live DOM property.
    #
    # @param [String] name
    #
    # @return [String, nil]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.at_css("input").attribute("value") # => "Foo"
    #
    def attribute(name)
      evaluate("this.getAttribute(name)", name: name)
    end

    #
    # Returns the selected `option` nodes of a `select` element.
    #
    # @return [Array<Node>]
    #
    # @raise [JavaScriptError] when the node is not a `select`.
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.at_css("select#title").selected.map(&:text) # => ["Mrs"]
    #
    def selected
      evaluate(<<~JS)
        function() {
          if (this.nodeName.toLowerCase() !== 'select') {
            throw new Error('Element is not a <select> element.');
          }
          return Array.from(this).filter(option => option.selected);
        }
      JS
    end

    #
    # (chainable) Selects options of a `select` element by the given
    # attribute.
    #
    # @param [Array<String>] values
    #   The value(s) to select. Accepts a string, multiple strings, or an
    #   array of strings.
    #
    # @param [Symbol] by
    #   The `option` attribute to match `values` against, e.g. `:value` or
    #   `:text`.
    #
    # @return [self]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.at_xpath("//*[select]").select(["1"]) # => Node (select)
    #   page.at_xpath("//*[select]").select(["text"], by: :text) # => Node (select)
    #
    # @example Accepts a string, multiple strings or an array of strings:
    #   page.at_xpath("//*[select]").select("1")
    #   page.at_xpath("//*[select]").select("1", "2")
    #   page.at_xpath("//*[select]").select(["1", "2"])
    #
    def select(*values, by: :value)
      tap do
        execute(<<~JS, values.flatten, by)
          function(values, by) {
            if (this.nodeName.toLowerCase() !== 'select') {
              throw new Error('Element is not a <select> element.');
            }
            const options = Array.from(this.options);
            this.value = undefined;
            for (const option of options) {
              option.selected = values.some((value) => option[by] === value);
              if (option.selected && !this.multiple) break;
            }
            this.dispatchEvent(new Event('input', { bubbles: true }));
            this.dispatchEvent(new Event('change', { bubbles: true }));
          }
        JS
      end
    end

    #
    # Evaluates JavaScript with `this` bound to the node, and returns the
    # result serialized into Ruby. Takes the same script shapes and arguments
    # as {Frame::Runtime#evaluate}. Arrow functions don't get `this`, so use a
    # `function` declaration when the script needs it.
    #
    # @param (see Frame::Runtime#evaluate)
    # @option (see Frame::Runtime#evaluate)
    #
    # @return [Object]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.at_css("input").evaluate("this.value")
    #   page.at_css("input").evaluate("this.value + suffix", suffix: "!")
    #
    def evaluate(expression, *positional, **keywords)
      @runtime.evaluate_in(self, expression, positional, keywords, mode: :value)
    end

    #
    # Same as {#evaluate}, but returns a {RemoteObject} that stays in the
    # browser instead of being serialized.
    #
    # @param (see Frame::Runtime#evaluate)
    # @option (see Frame::Runtime#evaluate)
    #
    # @return [RemoteObject, Node, Object]
    #   A {Node} for a node and the value itself for a primitive.
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.at_css("form").evaluate_handle("this.dataset") # => RemoteObject
    #   page.at_css("form").evaluate_handle("this") # => Node
    #
    def evaluate_handle(expression, *positional, **keywords)
      @runtime.evaluate_in(self, expression, positional, keywords, mode: :handle)
    end

    #
    # Runs JavaScript with `this` bound to the node, for its side effects.
    # The script is used as a function body, so multiple statements need no
    # wrapping.
    #
    # @param (see Frame::Runtime#evaluate)
    # @option (see Frame::Runtime#evaluate)
    #
    # @return [Boolean]
    #   Always `true`.
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.at_css("input").execute("this.value = text", text: "hello")
    #
    def execute(expression, *positional, **keywords)
      @runtime.evaluate_in(self, expression, positional, keywords, mode: :none)
      true
    end

    #
    # Two nodes are equal when they belong to the same target and share the
    # same backend node id.
    #
    # @param [Object] other
    #
    # @return [Boolean]
    #
    def ==(other)
      return false unless other.is_a?(Node)

      # We compare backendNodeId because once nodeId is sent to frontend backend
      # never returns same nodeId sending 0. In other words frontend is
      # responsible for keeping track of node ids.
      target_id == other.target_id && backend_node_id == other.backend_node_id
    end

    #
    # A developer-friendly string representation of the node.
    #
    # @return [String]
    #
    def inspect
      %(#<#{self.class} @target_id=#{@target_id.inspect} @node_id=#{@node_id} ) +
        %(@backend_node_id=#{@backend_node_id} @tag_name=#{@tag_name.inspect}>)
    end

    #
    # Finds the x, y coordinates to click or hover on the node.
    #
    # @param [Integer, nil] x
    #   Horizontal offset from the reference point.
    #
    # @param [Integer, nil] y
    #   Vertical offset from the reference point.
    #
    # @param [Symbol] position
    #   `:top` to offset from the node's top-left corner, `:center` to offset
    #   from its center.
    #
    # @return [(Float, Float)]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.at_css("input").find_position # => [126.7, 401.4]
    #   page.at_css("input").find_position(x: 5, y: 5) # => [55.2, 395.9]
    #   page.at_css("input").find_position(x: 5, y: 5, position: :center) # => [131.7, 406.4]
    #
    def find_position(x: nil, y: nil, position: :top)
      points = settled_quads.map { |q| to_points(q) }.first
      get_position(points, x, y, position)
    rescue CoordinatesNotFoundError
      x, y = bounding_rect_coordinates
      raise if x.zero? && y.zero?

      [x, y]
    end

    #
    # The computed CSS styles of the node.
    #
    # @return [Hash{String => String}]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.at_css("a").computed_style["display"] # => "inline"
    #
    def computed_style
      page
        .command("CSS.getComputedStyleForNode", nodeId: node_id)["computedStyle"]
        .each_with_object({}) { |style, memo| memo.merge!(style["name"] => style["value"]) }
    end

    # Returns the computed accessibility node for the element, or nil if the
    # element is ignored by the accessibility tree.
    #
    # @return [Accessibility::AXNode, nil]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.at_css("a").ax_node.role # => "link"
    #
    def ax_node
      page.accessibility.node_for(self)
    end

    #
    # @deprecated Will be removed in Ferrum 0.22. Use {#ax_node}.
    #
    # @return [Accessibility::AXNode, nil]
    #
    # @raise [TimeoutError]
    #
    def axnode
      Utils::Deprecate.warn("axnode will be removed in Ferrum 0.22. Use ax_node instead.", user_code: true)
      ax_node
    end

    #
    # Removes the node from the DOM.
    #
    # @return [Hash{String => Object}]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.at_css("#ad").remove
    #
    def remove
      page.command("DOM.removeNode", nodeId: node_id)
    end

    # Whether the node still exists in the DOM.
    #
    # @return [Boolean]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   node = page.at_css("#ad")
    #   node.remove
    #   node.exists? # => false
    #
    def exists?
      page.command("DOM.resolveNode", nodeId: node_id)
      true
    rescue Ferrum::NodeNotFoundError
      false
    end

    private

    def bounding_rect_coordinates
      evaluate(<<~JS)
        function() {
          const { left, top, width, height } = this.getBoundingClientRect();
          return [left + (width / 2), top + (height / 2)];
        }
      JS
    end

    def content_quads
      quads = page.command("DOM.getContentQuads", nodeId: node_id)["quads"]
      raise CoordinatesNotFoundError, "Node is either not visible or not an HTMLElement" if quads.empty?

      quads
    end

    def settled_quads(delay: MOVING_WAIT_DELAY, attempts: MOVING_WAIT_ATTEMPTS)
      Utils::Attempt.with_retry(errors: NodeMovingError, max: attempts, wait: 0) do
        previous, current = content_quads_with(delay: delay)
        raise NodeMovingError.new(self, previous, current) if previous != current

        current
      end
    end

    def content_quads_with(delay: MOVING_WAIT_DELAY)
      previous = content_quads
      sleep(delay)
      current = content_quads
      [previous, current]
    end

    def get_position(points, offset_x, offset_y, position)
      x = y = nil

      if offset_x && offset_y && position == :top
        point = points.first
        x = point[:x] + offset_x.to_i
        y = point[:y] + offset_y.to_i
      else
        x, y = points.inject([0, 0]) do |memo, coordinate|
          [memo[0] + coordinate[:x],
           memo[1] + coordinate[:y]]
        end

        x /= 4
        y /= 4
      end

      if offset_x && offset_y && position == :center
        x += offset_x.to_i
        y += offset_y.to_i
      end

      [x, y]
    end

    def to_points(quad)
      [{ x: quad[0], y: quad[1] },
       { x: quad[2], y: quad[3] },
       { x: quad[4], y: quad[5] },
       { x: quad[6], y: quad[7] }]
    end
  end
end
