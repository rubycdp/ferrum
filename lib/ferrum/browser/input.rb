module Ferrum
  class Browser
    module Input
      KEYS = JSON.parse(File.read(File.expand_path("../input.json", __FILE__)))
      MODIFIERS = { "alt" => 1, "ctrl" => 2, "control" => 2, "meta" => 4, "command" => 4, "shift" => 8 }
      KEYS_MAPPING = {
        cancel: "Cancel", help: "Help", backspace: "Backspace", tab: "Tab",
        clear: "Clear", return: "Enter", enter: "Enter", shift: "Shift",
        ctrl: "Control", control: "Control", alt: "Alt", pause: "Pause",
        escape: "Escape", space: "Space",  pageup: "PageUp", page_up: "PageUp",
        pagedown: "PageDown", page_down: "PageDown", end: "End", home: "Home",
        left: "ArrowLeft", up: "ArrowUp", right: "ArrowRight",
        down: "ArrowDown", insert: "Insert", delete: "Delete",
        semicolon: "Semicolon", equals: "Equal", numpad0: "Numpad0",
        numpad1: "Numpad1", numpad2: "Numpad2", numpad3: "Numpad3",
        numpad4: "Numpad4", numpad5: "Numpad5", numpad6: "Numpad6",
        numpad7: "Numpad7", numpad8: "Numpad8", numpad9: "Numpad9",
        multiply: "NumpadMultiply", add: "NumpadAdd",
        separator: "NumpadDecimal", subtract: "NumpadSubtract",
        decimal: "NumpadDecimal", divide: "NumpadDivide", f1: "F1", f2: "F2",
        f3: "F3", f4: "F4", f5: "F5", f6: "F6", f7: "F7", f8: "F8", f9: "F9",
        f10: "F10", f11: "F11", f12: "F12", meta: "Meta", command: "Meta",
      }

      def click(node, keys = [], offset = {})
        x, y, modifiers = prepare_before_click(__method__, node, keys, offset)
        command("Input.dispatchMouseEvent", type: "mousePressed", modifiers: modifiers, button: "left", x: x, y: y, clickCount: 1)
        @wait = 0.05 # Potential wait because if network event is triggered then we have to wait until it's over.
        command("Input.dispatchMouseEvent", type: "mouseReleased", modifiers: modifiers, button: "left", x: x, y: y, clickCount: 1)
      end

      def right_click(node, keys = [], offset = {})
        x, y, modifiers = prepare_before_click(__method__, node, keys, offset)
        command("Input.dispatchMouseEvent", type: "mousePressed", modifiers: modifiers, button: "right", x: x, y: y, clickCount: 1)
        command("Input.dispatchMouseEvent", type: "mouseReleased", modifiers: modifiers, button: "right", x: x, y: y, clickCount: 1)
      end

      def double_click(node, keys = [], offset = {})
        x, y, modifiers = prepare_before_click(__method__, node, keys, offset)
        command("Input.dispatchMouseEvent", type: "mousePressed", modifiers: modifiers, button: "left", x: x, y: y, clickCount: 2)
        command("Input.dispatchMouseEvent", type: "mouseReleased", modifiers: modifiers, button: "left", x: x, y: y, clickCount: 2)
      end

      def click_coordinates(x, y)
        command("Input.dispatchMouseEvent", type: "mousePressed", button: "left", x: x, y: y, clickCount: 1)
        @wait = 0.05 # Potential wait because if network event is triggered then we have to wait until it's over.
        command("Input.dispatchMouseEvent", type: "mouseReleased", button: "left", x: x, y: y, clickCount: 1)
      end

      def hover(node)
        evaluate_on(node: node, expr: "_cuprite.scrollIntoViewport(this)")
        x, y = calculate_quads(node)
        command("Input.dispatchMouseEvent", type: "mouseMoved", x: x, y: y)
      end

      def set(node, value)
        object_id = command("DOM.resolveNode", nodeId: node["nodeId"]).dig("object", "objectId")
        evaluate("_cuprite.set(arguments[0], arguments[1])", { "objectId" => object_id }, value)
      end

      def drag(node, other)
        raise NotImplementedError
      end

      def drag_by(node, x, y)
        raise NotImplementedError
      end

      def select(node, value)
        evaluate_on(node: node, expr: "_cuprite.select(this, #{value})")
      end

      def trigger(node, event)
        options = event.to_s == "click" ? { wait: 0.1 } : {}
        evaluate_on(node: node, expr: %(_cuprite.trigger(this, "#{event}")), **options)
      end

      def scroll_to(top, left)
        execute("window.scrollTo(#{top}, #{left})")
      end

      def send_keys(node, keys)
        keys = normalize_keys(Array(keys))

        click(node) if !evaluate_on(node: node, expr: %(_cuprite.containsSelection(this)))

        keys.each do |key|
          type = key[:text] ? "keyDown" : "rawKeyDown"
          command("Input.dispatchKeyEvent", type: type, **key)
          command("Input.dispatchKeyEvent", type: "keyUp", **key)
        end
      end

      def normalize_keys(keys, pressed_keys = [], memo = [])
        case keys
        when Array
          pressed_keys.push([])
          memo += combine_strings(keys).map { |k| normalize_keys(k, pressed_keys, memo) }
          pressed_keys.pop
          memo.flatten.compact
        when Symbol
          key = keys.to_s.downcase

          if MODIFIERS.keys.include?(key)
            pressed_keys.last.push(key)
            nil
          else
            _key = KEYS.fetch(KEYS_MAPPING[key.to_sym] || key.to_sym)
            _key[:modifiers] = pressed_keys.flatten.map { |k| MODIFIERS[k] }.reduce(0, :|)
            to_options(_key)
          end
        when String
          pressed = pressed_keys.flatten
          keys.each_char.map do |char|
            if pressed.empty?
              key = KEYS[char] || {}
              key = key.merge(text: char, unmodifiedText: char)
              [to_options(key)]
            else
              key = KEYS[char] || {}
              text = pressed == ["shift"] ? char.upcase : char
              key = key.merge(
                text: text,
                unmodifiedText: text,
                isKeypad: key["location"] == 3,
                modifiers: pressed.map { |k| MODIFIERS[k] }.reduce(0, :|),
              )

              modifiers = pressed.map { |k| to_options(KEYS.fetch(KEYS_MAPPING[k.to_sym])) }
              modifiers + [to_options(key)]
            end.flatten
          end
        end
      end

      def combine_strings(keys)
        keys
          .chunk { |k| k.is_a?(String) }
          .map { |s, k| s ? [k.reduce(&:+)] : k }
          .reduce(&:+)
      end

      private

      def prepare_before_click(name, node, keys, offset)
        evaluate_on(node: node, expr: "_cuprite.scrollIntoViewport(this)")
        x, y = calculate_quads(node, offset[:x], offset[:y])
        evaluate_on(node: node, expr: "_cuprite.mouseEventTest(this, '#{name}', #{x}, #{y})")

        modifiers = keys.map { |k| MODIFIERS[k.to_s] }.compact.reduce(0, :|)

        command("Input.dispatchMouseEvent", type: "mouseMoved", x: x, y: y)

        [x, y, modifiers]
      end

      def calculate_quads(node, offset_x = nil, offset_y = nil)
        quads = get_content_quads(node)
        offset_x, offset_y = offset_x.to_i, offset_y.to_i

        if offset_x > 0 || offset_y > 0
          point = quads.first
          [point[:x] + offset_x, point[:y] + offset_y]
        else
          x, y = quads.inject([0, 0]) do |memo, point|
            [memo[0] + point[:x],
             memo[1] + point[:y]]
          end
          [x / 4, y / 4]
        end
      end

      def get_content_quads(node)
        begin
          result = command("DOM.getContentQuads", nodeId: node["nodeId"])
        rescue BrowserError => e
          if e.message == "Could not compute content quads."
            raise MouseEventFailed.new("MouseEventFailed: click, none, 0, 0")
          else
            raise
          end
        end

        raise "Node is either not visible or not an HTMLElement" if result["quads"].size == 0

        # FIXME: Case when a few quads returned
        result["quads"].map do |quad|
          [{x: quad[0], y: quad[1]},
           {x: quad[2], y: quad[3]},
           {x: quad[4], y: quad[5]},
           {x: quad[6], y: quad[7]}]
        end.first
      end

      def to_options(hash)
        hash.inject({}) { |memo, (k, v)| memo.merge(k.to_sym => v) }
      end
    end
  end
end
