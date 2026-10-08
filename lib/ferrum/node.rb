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

    attr_reader :page, :target_id, :description, :tag_name

    def initialize(frame, target_id, description, object_id: nil, node_id: nil)
      @page = frame.page
      @target_id = target_id
      @description = description
      @tag_name = description["nodeName"].downcase
      @object_id = object_id
      @node_id = node_id
    end

    # Frontend node id is resolved lazily, on first actual need (focus, click, scroll_into_view, etc.)
    # We can try to subscribe to `DOM.childNodeRemoved` and `DOM.childNodeInserted` in the future
    # to keep track of nodes.
    def node_id
      @node_id ||= begin
        id = page.command("DOM.requestNode", objectId: @object_id)["nodeId"]
        raise NodeNotFoundError, "node is not trackable" if id.zero?

        id
      rescue NoExecutionContextError
        raise NodeNotFoundError, "node is not trackable"
      end
    end

    # Whether this is an element node, as opposed to e.g. a text node.
    #
    # @return [Boolean]
    def node?
      description["nodeType"] == 1 # nodeType: 3, nodeName: "#text" e.g.
    end

    #
    # The id of the frame this node belongs to.
    #
    # @return [String]
    #
    def frame_id
      description["frameId"]
    end

    #
    # The {Frame} this node belongs to. Keep using finder methods (`at_css`,
    # `at_xpath`, etc.) on it to search within that frame, e.g. inside an
    # `iframe`.
    #
    # @return [Frame, nil]
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
    # @example
    #   input = page.at_css("input[name='q']")
    #   input.focus
    #
    def focus
      tap { page.command("DOM.focus", slowmoable: true, nodeId: node_id) }
    end

    # Whether the node can receive focus. Attempts to {#focus} the node to
    # find out.
    #
    # @return [Boolean]
    def focusable?
      focus
      true
    rescue BrowserError => e
      e.message == "Element is not focusable" ? false : raise
    end

    #
    # Waits until the node's position stops changing, retrying up to
    # `attempts` times. Raises {NodeMovingError} if the node is still moving
    # after the last attempt.
    #
    # @param [Float] delay
    #   Seconds to wait between two position checks.
    #
    # @param [Integer] attempts
    #   Maximum number of attempts before raising.
    #
    # @return [Array]
    #   The content quads of the node once it has stopped moving.
    #
    def wait_for_stop_moving(delay: MOVING_WAIT_DELAY, attempts: MOVING_WAIT_ATTEMPTS)
      Utils::Attempt.with_retry(errors: NodeMovingError, max: attempts, wait: 0) do
        previous, current = content_quads_with(delay: delay)
        raise NodeMovingError.new(self, previous, current) if previous != current

        current
      end
    end

    # Checks whether the node's position has stopped changing, by comparing
    # two content-quad snapshots taken `delay` seconds apart.
    #
    # @param [Float] delay
    #   Seconds to wait between the two position checks.
    #
    # @return [Boolean]
    def moving?(delay: MOVING_WAIT_DELAY)
      previous, current = content_quads_with(delay: delay)
      previous == current
    end

    #
    # Removes focus from the node.
    #
    # @return [self]
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
    # @return [self]
    #
    # @example
    #   input.focus.type("Input")
    #
    def type(*keys)
      tap { page.keyboard.type(*keys) }
    end

    # mode: (:left | :right | :double)
    # keys: (:alt, (:ctrl | :control), (:meta | :command), :shift)
    # offset: { :x, :y, :position (:top | :center) }
    def click(mode: :left, keys: [], offset: {}, delay: 0)
      x, y = find_position(**offset)
      modifiers = page.keyboard.modifiers(keys)

      # `:right` and `:double` pass `wait: 0` to preserve the historical
      # no-network-wait default of `Mouse#up` and `Mouse#down`
      case mode
      when :right
        page.mouse.click(x:, y:, modifiers:, delay:, button: :right, wait: 0)
      when :double
        page.mouse.click(x:, y:, modifiers:, delay:, count: 2, wait: 0)
      when :left
        page.mouse.click(x:, y:, modifiers:, delay:)
      end

      self
    end

    # Not currently implemented.
    #
    # @raise [NotImplementedError] always
    def hover
      raise NotImplementedError
    end

    #
    # Scrolls the node into view if it is not already visible.
    #
    # @return [self]
    #
    # @example
    #   page.at_css("#footer").scroll_into_view
    #
    def scroll_into_view
      tap { page.command("DOM.scrollIntoViewIfNeeded", nodeId: node_id) }
    end

    # Whether the node's bounding rect is fully within the viewport (or,
    # when `of:` is given, within that scoping element's bounds).
    #
    # @param [Node, nil] of
    #   An element to use as the visible bounds instead of the window.
    #
    # @return [Boolean]
    def in_viewport?(of: nil)
      evaluate(<<~JS, scope: of)
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
    # @example
    #   page.at_css("input[type=file]").select_file("/path/to/file.png")
    #
    def select_file(value)
      page.command(
        "DOM.setFileInputFiles",
        slowmoable: true,
        backendNodeId: description["backendNodeId"],
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
    # @example
    #   page.at_xpath("//iframe").at_xpath(".//a") # => Node
    #
    def at_xpath(selector)
      page.at_xpath(selector, within: self)
    end

    #
    # Finds a node by CSS selector, scoped to search within this node. Runs
    # `querySelector` within this node.
    #
    # @param [String] selector
    #
    # @return [Node, nil]
    #
    # @example
    #   page.at_css("form").at_css("input[name='q']") # => Node
    #
    def at_css(selector)
      page.at_css(selector, within: self)
    end

    #
    # Finds nodes by xpath, scoped to search within this node. Runs
    # `document.evaluate` within this node.
    #
    # @param [String] selector
    #
    # @return [Array<Node>]
    #
    # @example
    #   page.at_css("ul").xpath(".//li") # => [Node]
    #
    def xpath(selector)
      page.xpath(selector, within: self)
    end

    #
    # Finds nodes by CSS selector, scoped to search within this node. Runs
    # `querySelectorAll` within this node.
    #
    # @param [String] selector
    #
    # @return [Array<Node>]
    #
    # @example
    #   page.at_css("ul").css("li") # => [Node]
    #
    def css(selector)
      page.css(selector, within: self)
    end

    #
    # The node's text content, i.e. `textContent`.
    #
    # @return [String]
    #
    # @example
    #   page.at_css("a > h3").text # => "rubycdp/ferrum: Ruby Chrome/Chromium driver - GitHub"
    #
    def text
      evaluate("this.textContent")
    end

    # FIXME: clear API for text and inner_text
    def inner_text
      evaluate("this.innerText")
    end

    #
    # The node's `value` property. Useful for form elements such as `input`,
    # `select` and `textarea`.
    #
    # @return [Object]
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
    # @example
    #   page.at_css("input").property("value") # => "Foo"
    #
    def property(name)
      evaluate("this['#{name}']")
    end
    alias [] property

    #
    # Returns the value of the given HTML attribute, i.e.
    # `getAttribute(name)`. Unlike {#property}, it reads the attribute as
    # defined in markup rather than the live DOM property.
    #
    # @param [String] name
    #
    # @return [String, nil]
    #
    # @example
    #   page.at_css("input").attribute("value") # => "Foo"
    #
    def attribute(name)
      evaluate("this.getAttribute('#{name}')")
    end

    #
    # Returns the selected `option` nodes of a `select` element.
    #
    # @return [Array<Node>]
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
        execute(<<~JS, values: values.flatten, by: by)
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
    # result serialized into Ruby. Takes the same script shapes and named
    # arguments as {Frame::Runtime#evaluate}.
    #
    # @param [String] expression
    #   A JavaScript expression, or a function declaration.
    #
    # @param [Numeric, nil] timeout
    #   How long to wait for the script to settle, in seconds.
    #
    # @param [Hash, nil] args
    #   Arguments to pass, when a name would collide with a reserved keyword.
    #
    # @param [Hash] named
    #   Arguments to pass, becoming the function's parameters in order.
    #
    # @return [Object]
    #
    # @example
    #   page.at_css("input").evaluate("this.value")
    #   page.at_css("input").evaluate("this.value + suffix", suffix: "!")
    #   page.at_css("input").evaluate("this.parentNode") # => Ferrum::Node
    #
    def evaluate(expression, *positional, timeout: nil, args: nil, **named)
      page.evaluate_in(self, expression, positional, (args || {}).merge(named),
                       mode: :value, timeout: timeout)
    end

    #
    # Same as {#evaluate}, but returns a {RemoteObject} that stays in the
    # browser instead of being serialized.
    #
    # @param (see #evaluate)
    #
    # @return [RemoteObject, Node, Object]
    #
    def evaluate_handle(expression, *positional, timeout: nil, args: nil, **named)
      page.evaluate_in(self, expression, positional, (args || {}).merge(named),
                       mode: :handle, timeout: timeout)
    end

    #
    # Runs JavaScript with `this` bound to the node, for its side effects.
    # The script is used as a function body, so multiple statements need no
    # wrapping.
    #
    # @param (see #evaluate)
    #
    # @return [Boolean]
    #   Always `true`.
    #
    # @example
    #   page.at_css("input").execute("this.value = text", text: "hello")
    #
    def execute(expression, *positional, timeout: nil, args: nil, **named)
      page.evaluate_in(self, expression, positional, (args || {}).merge(named),
                       mode: :none, timeout: timeout)
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
      target_id == other.target_id && description["backendNodeId"] == other.description["backendNodeId"]
    end

    #
    # A developer-friendly string representation of the node.
    #
    # @return [String]
    #
    def inspect
      %(#<#{self.class} @target_id=#{@target_id.inspect} @node_id=#{@node_id} @description=#{@description.inspect}>)
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
    # @return [(Integer, Integer)]
    #
    def find_position(x: nil, y: nil, position: :top)
      points = wait_for_stop_moving.map { |q| to_points(q) }.first
      get_position(points, x, y, position)
    rescue CoordinatesNotFoundError
      x, y = bounding_rect_coordinates
      raise if x.zero? && y.zero?

      [x, y]
    end

    # Returns a hash of the computed styles for the node
    def computed_style
      page
        .command("CSS.getComputedStyleForNode", nodeId: node_id)["computedStyle"]
        .each_with_object({}) { |style, memo| memo.merge!(style["name"] => style["value"]) }
    end

    # Returns the computed accessibility node for the element, or nil if the
    # element is ignored by the accessibility tree.
    #
    # @return [Accessibility::AXNode, nil]
    def axnode
      page.accessibility.node_for(self)
    end

    #
    # Removes the node from the DOM.
    #
    # @return [Hash{String => Object}]
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
    def exists?
      page.command("DOM.resolveNode", nodeId: node_id)
      true
    rescue Ferrum::NodeNotFoundError
      false
    end

    private

    def bounding_rect_coordinates
      evaluate <<~JS
        [this.getBoundingClientRect().left + window.pageXOffset + (this.offsetWidth / 2),
         this.getBoundingClientRect().top + window.pageYOffset + (this.offsetHeight / 2)]
      JS
    end

    def content_quads
      quads = page.command("DOM.getContentQuads", nodeId: node_id)["quads"]
      raise CoordinatesNotFoundError, "Node is either not visible or not an HTMLElement" if quads.empty?

      quads
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
