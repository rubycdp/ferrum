# frozen_string_literal: true

module Ferrum
  #
  # Simulates mouse input for a page via the CDP `Input.dispatchMouseEvent`
  # command, and page scrolling via JavaScript. Keeps track of the current
  # pointer position and pressed buttons so `move`, `down`, `up` and `click`
  # can be composed while reporting consistent state to Chrome.
  #
  class Mouse
    BUTTON_MASKS = {
      "none" => 0,
      "left" => 1,
      "right" => 2,
      "middle" => 4,
      "back" => 8,
      "forward" => 16
    }.freeze

    def initialize(page)
      @page = page
      @x = @y = 0
      @buttons = 0
    end

    #
    # Scrolls the page by the given amount. Scrolls instantly, even when the
    # page sets `scroll-behavior: smooth`.
    #
    # @param [Numeric] x
    #   The horizontal pixel value that you want to scroll by.
    #
    # @param [Numeric] y
    #   The vertical pixel value that you want to scroll by.
    #
    # @return [self]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   browser.go_to("https://www.google.com/search?q=Ruby+headless+driver+for+Capybara")
    #   browser.mouse.scroll_by(y: 400)
    #
    def scroll_by(x: 0, y: 0)
      tap { @page.execute("window.scrollBy({ left: x, top: y, behavior: 'instant' })", x:, y:) }
    end

    #
    # Scrolls the page to the given coordinates. Scrolls instantly, even when
    # the page sets `scroll-behavior: smooth`.
    #
    # @param [Numeric, nil] x
    #   The pixel along the horizontal axis of the document that you want
    #   displayed in the upper left. If omitted, keeps the current one.
    #
    # @param [Numeric, nil] y
    #   The pixel along the vertical axis of the document that you want
    #   displayed in the upper left. If omitted, keeps the current one.
    #
    # @return [self]
    #
    # @raise [TimeoutError]
    #
    # @example
    #   browser.go_to("https://www.google.com/search?q=Ruby+headless+driver+for+Capybara")
    #   browser.mouse.scroll_to(x: 0, y: 400)
    #   browser.mouse.scroll_to(y: 0)
    #
    def scroll_to(x: nil, y: nil)
      tap do
        @page.execute("window.scrollTo({ left: x ?? undefined, top: y ?? undefined, behavior: 'instant' })", x:, y:)
      end
    end

    #
    # Click given coordinates, fires mouse move, down and up events.
    #
    # @param [Integer] x
    #
    # @param [Integer] y
    #
    # @param [Float] delay
    #   Delay between mouse down and mouse up events.
    #
    # @param [Numeric, false] navigation_wait
    #   Seconds to watch for a navigation started by the click, then wait for it
    #   to load. `false` returns as soon as the click is dispatched.
    #
    # @param [Numeric, Deadline, nil] timeout
    #   How long the click and the page load it starts may take together, the page timeout by default.
    #
    # @param [Hash{Symbol => Object}] options
    #   Additional keyword arguments.
    #
    # @option options [:left, :right, :middle, :back, :forward] :button (:left)
    #   The mouse button to click.
    #
    # @option options [Integer] :count (1)
    #
    # @option options [Array<Symbol>, Integer] :modifiers
    #   Modifier keys to hold: `:alt`, `:ctrl` (or `:control`), `:meta` (or
    #   `:command`) and `:shift`, or CDP's `modifiers` bitfield.
    #   If omitted, uses the keys held by `keyboard.hold`, or none outside of it.
    #
    # @return [self]
    #
    # @raise [TimeoutError]
    #
    def click(x:, y:, delay: 0, navigation_wait: Page::NAVIGATION_WAIT, timeout: nil, **options)
      deadline = Deadline.wrap(timeout || @page.timeout)
      Deadline.within(deadline) do
        move(x: x, y: y, modifiers: options[:modifiers])
        down(**options)
        sleep(delay)
        # Potential wait because if some network event is triggered then we have
        # to wait until it's over and frame is loaded or failed to load.
        up(navigation_wait: navigation_wait, timeout: deadline, **options)
      end
      self
    end

    #
    # Mouse down for given coordinates.
    #
    # @param [Hash{Symbol => Object}] options
    #   Additional keyword arguments.
    #
    # @option options [:left, :right, :middle, :back, :forward] :button (:left)
    #   The mouse button to click.
    #
    # @option options [Integer] :count (1)
    #
    # @option options [Array<Symbol>, Integer] :modifiers
    #   Modifier keys to hold: `:alt`, `:ctrl` (or `:control`), `:meta` (or
    #   `:command`) and `:shift`, or CDP's `modifiers` bitfield.
    #   If omitted, uses the keys held by `keyboard.hold`, or none outside of it.
    #
    # @return [self]
    #
    # @raise [TimeoutError]
    #
    def down(**options)
      tap { mouse_event(type: "mousePressed", **options) }
    end

    #
    # Mouse up for given coordinates.
    #
    # @param [Hash{Symbol => Object}] options
    #   Additional keyword arguments.
    #
    # @option options [:left, :right, :middle, :back, :forward] :button (:left)
    #   The mouse button to click.
    #
    # @option options [Integer] :count (1)
    #
    # @option options [Array<Symbol>, Integer] :modifiers
    #   Modifier keys to hold: `:alt`, `:ctrl` (or `:control`), `:meta` (or
    #   `:command`) and `:shift`, or CDP's `modifiers` bitfield.
    #   If omitted, uses the keys held by `keyboard.hold`, or none outside of it.
    #
    # @option options [Numeric, false] :navigation_wait (false)
    #   Seconds to watch for a navigation started by releasing the button, then wait for it to load.
    #
    # @option options [Numeric, Deadline] :timeout
    #   How long the event and the page load it starts may take together, the page timeout by default.
    #
    # @return [self]
    #
    # @raise [TimeoutError]
    #
    def up(**options)
      tap { mouse_event(type: "mouseReleased", **options) }
    end

    #
    # Mouse move to given x and y.
    #
    # @param [Number] x
    #
    # @param [Number] y
    #
    # @param [Integer] steps
    #   Sends intermediate mousemove events.
    #
    # @param [Array<Symbol>, Integer, nil] modifiers
    #   Modifier keys to hold: `:alt`, `:ctrl` (or `:control`), `:meta` (or
    #   `:command`) and `:shift`, or CDP's `modifiers` bitfield.
    #   If omitted, uses the keys held by `keyboard.hold`, or none outside of it.
    #
    # @param [Numeric, Deadline, nil] timeout
    #   How long all the steps may take together, the page timeout by default.
    #
    # @return [self]
    #
    # @raise [TimeoutError]
    #
    def move(x:, y:, steps: 1, modifiers: nil, timeout: nil)
      from_x = @x
      from_y = @y
      @x = x
      @y = y
      button = pressed_button
      modifiers = modifiers_mask(modifiers)

      Deadline.within(timeout || @page.timeout) do
        steps.times do |i|
          new_x = from_x + ((@x - from_x) * ((i + 1) / steps.to_f))
          new_y = from_y + ((@y - from_y) * ((i + 1) / steps.to_f))

          @page.command("Input.dispatchMouseEvent",
                        slowmoable: true,
                        type: "mouseMoved",
                        x: new_x,
                        y: new_y,
                        button: button,
                        buttons: @buttons,
                        modifiers: modifiers)
        end
      end

      self
    end

    private

    def mouse_event(type:, button: :left, count: 1, modifiers: nil, navigation_wait: false, timeout: nil)
      button = validate_button(button)
      register_event_button(type, button)
      options = { x: @x, y: @y, type: type, button: button, buttons: @buttons, clickCount: count,
                  modifiers: modifiers_mask(modifiers) }
      if !navigation_wait || navigation_wait.zero?
        return @page.command("Input.dispatchMouseEvent", slowmoable: true, **options)
      end

      deadline = Deadline.wrap(timeout || @page.timeout)
      result = nil
      @page.await_navigation!(watch: navigation_wait, timeout: deadline) do
        result = @page.command("Input.dispatchMouseEvent", slowmoable: true, timeout: deadline, **options)
      end
      result
    end

    def modifiers_mask(modifiers)
      case modifiers
      when nil then @page.keyboard.held_modifiers
      when Integer then modifiers
      else @page.keyboard.modifiers(modifiers)
      end
    end

    def validate_button(button)
      button = button.to_s
      raise "Invalid button: #{button}" unless BUTTON_MASKS.key?(button)

      button
    end

    def pressed_button
      BUTTON_MASKS.find { |_name, mask| mask.positive? && @buttons.anybits?(mask) }&.first || "none"
    end

    def register_event_button(type, button)
      case type
      when "mousePressed"
        @buttons |= BUTTON_MASKS[button]
      when "mouseReleased"
        @buttons &= ~BUTTON_MASKS[button]
      end
    end
  end
end
