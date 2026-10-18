# frozen_string_literal: true

require "json"

module Ferrum
  #
  # Simulates keyboard input for a page via the CDP `Input.dispatchKeyEvent`
  # command. Provides low-level `down`/`up` for individual keys as well as
  # `type` for typing a sequence of characters/keys, translating key names
  # and modifier chords into the CDP key event parameters Chrome expects.
  #
  class Keyboard
    KEYS = JSON.parse(File.read(File.expand_path("keyboard.json", __dir__)))
    MODIFIERS = { "alt" => 1, "ctrl" => 2, "control" => 2,
                  "meta" => 4, "command" => 4, "shift" => 8 }.freeze
    KEYS_MAPPING = {
      cancel: "Cancel", help: "Help", backspace: "Backspace", tab: "Tab",
      clear: "Clear", return: "Enter", enter: "Enter", shift: "Shift",
      ctrl: "Control", control: "Control", alt: "Alt", pause: "Pause",
      escape: "Escape", space: "Space", pageup: "PageUp", page_up: "PageUp",
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
      f10: "F10", f11: "F11", f12: "F12", meta: "Meta", command: "Meta"
    }.freeze

    # Modifier keys currently pressed by {#hold}, in the same format as
    # {#modifiers} returns. It's 0 outside a {#hold} block.
    #
    # @return [Integer]
    attr_reader :held_modifiers

    def initialize(page)
      @page = page
      @held_modifiers = 0
    end

    #
    # Dispatches a `keydown` event.
    #
    # @param [String, Symbol] key
    #   Name of the key, such as `"a"`, `:enter`, or `:backspace`.
    #
    # @return [self]
    #
    # @raise [ArgumentError] If the key is a modifier, use {#hold} instead.
    #
    def down(key)
      reject_modifier(key)
      key = normalize_keys(Array(key)).first
      type = key[:text] ? "keyDown" : "rawKeyDown"
      @page.command("Input.dispatchKeyEvent", slowmoable: true, type: type, **key)
      self
    end

    #
    # Dispatches a `keyup` event.
    #
    # @param [String, Symbol] key
    #   Name of the key, such as `"a"`, `:enter`, or `:backspace`.
    #
    # @return [self]
    #
    # @raise [ArgumentError] If the key is a modifier, use {#hold} instead.
    #
    def up(key)
      reject_modifier(key)
      key = normalize_keys(Array(key)).first
      @page.command("Input.dispatchKeyEvent", slowmoable: true, type: "keyUp", **key)
      self
    end

    #
    # Sends a keydown, keypress/input, and keyup event for each character in
    # the text.
    #
    # @param [Array<String, Symbol, (Symbol, String)>] keys
    #   The text to type into a focused element, `[:Shift, "s"], "tring"`.
    #
    # @return [self]
    #
    def type(*keys)
      keys = normalize_keys(Array(keys))

      keys.each do |key|
        type = key[:text] ? "keyDown" : "rawKeyDown"
        @page.command("Input.dispatchKeyEvent", type: type, **key)
        @page.command("Input.dispatchKeyEvent", slowmoable: true, type: "keyUp", **key)
      end

      self
    end

    #
    # Holds modifier keys down while the block runs: every keyboard and mouse
    # event dispatched inside it carries them, and they are released when the
    # block returns or raises.
    #
    # @param [Array<:alt, :ctrl, :control, :meta, :command, :shift>] keys
    #
    # @yield The input to dispatch with the modifiers held.
    #
    # @return [Object] The block's value.
    #
    # @raise [ArgumentError] If no block is given or a key isn't a modifier.
    #
    # @example
    #   page.keyboard.hold(:shift) do
    #     page.mouse.move(x: 10, y: 10).down.move(x: 200, y: 200, steps: 10).up
    #   end
    #
    def hold(*keys)
      raise ArgumentError, "block is required" unless block_given?

      keys = keys.map { |key| modifier_name(key) || raise(ArgumentError, "not a modifier key: #{key.inspect}") }
      previous = @held_modifiers
      pressed = []

      begin
        keys.each { |key| press_modifier(key, pressed) }
        result = yield
        release_modifiers(pressed)
        result
      rescue StandardError
        release_modifiers(pressed, quietly: true)
        raise
      ensure
        @held_modifiers = previous
      end
    end

    #
    # Returns bitfield for a given keys.
    #
    # @param [Array<:alt, :ctrl, :command, :shift>] keys
    #
    # @return [Integer]
    #
    def modifiers(keys)
      keys.map { |k| MODIFIERS[k.to_s] }.compact.reduce(0, :|)
    end

    private

    def modifier_name(key)
      name = key.to_s.downcase
      name if MODIFIERS.key?(name)
    end

    def reject_modifier(key)
      return unless key.is_a?(Symbol) && modifier_name(key)

      raise ArgumentError, "#{key.inspect} is a modifier, use keyboard.hold(#{key.inspect}) { ... } instead"
    end

    def press_modifier(name, pressed)
      bit = MODIFIERS[name]
      return if @held_modifiers.anybits?(bit)

      @held_modifiers |= bit
      dispatch_modifier("rawKeyDown", name)
      pressed.push(name)
    end

    def release_modifiers(pressed, quietly: false)
      while (name = pressed.pop)
        @held_modifiers &= ~MODIFIERS[name]
        begin
          dispatch_modifier("keyUp", name)
        rescue Error
          raise unless quietly
        end
      end
    end

    def dispatch_modifier(type, name)
      key = to_options(KEYS.fetch(KEYS_MAPPING[name.to_sym]))
      @page.command("Input.dispatchKeyEvent", slowmoable: true, type: type, modifiers: @held_modifiers, **key)
    end

    # rubocop:disable Metrics/PerceivedComplexity
    # rubocop:disable Metrics/CyclomaticComplexity
    def normalize_keys(keys, pressed_keys = [], memo = [])
      case keys
      when Array
        raise ArgumentError, "empty keys passed" if keys.empty?

        pressed_keys.push([])
        memo += combine_strings(keys).map do |key|
          normalize_keys(key, pressed_keys, memo)
        end
        pressed_keys.pop
        memo.flatten.compact
      when Symbol
        key = keys.to_s.downcase

        if MODIFIERS.keys.include?(key)
          pressed_keys.last.push(key)
          nil
        else
          key = KEYS.fetch(KEYS_MAPPING[key.to_sym] || key.to_sym)
          key[:modifiers] = pressed_keys.flatten.map { |k| MODIFIERS[k] }.reduce(@held_modifiers, :|)
          to_options(key)
        end
      when String
        raise ArgumentError, "empty keys passed" if keys.empty?

        pressed = pressed_keys.flatten
        mask = pressed.map { |k| MODIFIERS[k] }.reduce(@held_modifiers, :|)
        keys.each_char.map do |char|
          key = KEYS[char] || {}

          if mask.zero?
            key = key.merge(text: char, unmodifiedText: char)
            [to_options(key)]
          else
            text = mask == MODIFIERS["shift"] ? char.upcase : char
            key = key.merge(
              text: text,
              unmodifiedText: text,
              isKeypad: key["location"] == 3,
              modifiers: mask
            )

            # Synthetic key events alone do not trigger the browser's editing
            # shortcuts (e.g. select-all). When the chord matches a platform
            # accelerator, name the editing command explicitly so Chrome
            # executes it via the CDP `commands` field.
            command = editing_command(mask, char)
            key = key.merge(commands: [command]) if command

            modifiers = pressed.map { |k| to_options(KEYS.fetch(KEYS_MAPPING[k.to_sym])) }
            modifiers + [to_options(key)]
          end.flatten
        end
      else
        raise ArgumentError, "unexpected argument"
      end
    end
    # rubocop:enable Metrics/PerceivedComplexity
    # rubocop:enable Metrics/CyclomaticComplexity

    def combine_strings(keys)
      keys
        .chunk { |k| k.is_a?(String) }
        .map { |s, k| s ? [k.reduce(&:+)] : k }
        .reduce(&:+)
    end

    def to_options(hash)
      hash.inject({}) { |memo, (k, v)| memo.merge(k.to_sym => v) }
    end

    # Names the CDP editing command for a modifier chord, or nil if the chord
    # is not an editing accelerator. The accelerator modifier is Cmd on macOS
    # and Ctrl elsewhere, matching Chrome's own key bindings. Currently only
    # select-all is mapped; extend the guard for further commands as needed.
    def editing_command(mask, char)
      return unless char.casecmp?("a")

      accelerator = Utils::Platform.mac? ? MODIFIERS["meta"] : MODIFIERS["ctrl"]
      "selectAll" if mask == accelerator
    end
  end
end
