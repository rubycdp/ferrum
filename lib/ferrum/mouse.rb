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
    # Scroll page by the given amount x, y. Scrolls instantly, even when the
    # page sets `scroll-behavior: smooth`.
    #
    # @param [Integer] x
    #  The horizontal pixel value that you want to scroll by.
    #
    # @param [Integer] y
    #   The vertical pixel value that you want to scroll by.
    #
    # @raise [TimeoutError]
    #
    # @example
    #   browser.go_to("https://www.google.com/search?q=Ruby+headless+driver+for+Capybara")
    #   browser.mouse.scroll_by(0, 400)
    #
    def scroll_by(x, y)
      tap { @page.execute("window.scrollBy({ left: #{x}, top: #{y}, behavior: 'instant' })") }
    end

    #
    # Scroll page to a given x, y coordinates. Scrolls instantly, even when
    # the page sets `scroll-behavior: smooth`.
    #
    # @param [Integer] x
    #  The pixel along the horizontal axis of the document that you want
    #  displayed in the upper left.
    #
    # @param [Integer] y
    #   The pixel along the vertical axis of the document that you want
    #   displayed in the upper left.
    #
    # @raise [TimeoutError]
    #
    # @example
    #   browser.go_to("https://www.google.com/search?q=Ruby+headless+driver+for+Capybara")
    #   browser.mouse.scroll_to(0, 400)
    #
    def scroll_to(x, y)
      tap { @page.execute("window.scrollTo({ left: #{x}, top: #{y}, behavior: 'instant' })") }
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
    # @param [Numeric] navigation_wait
    #   Seconds to watch for a navigation started by the click, then wait for it
    #   to load. `0` returns as soon as the click is dispatched.
    #
    # @param [Numeric, nil] wait
    #   Deprecated, renamed to `navigation_wait`.
    #
    # @param [Numeric, Deadline, nil] timeout
    #   How long the click and the page load it starts may take together, the page timeout by default.
    #
    # @param [Hash{Symbol => Object}] options
    #   Additional keyword arguments.
    #
    # @option options [:left, :right] :button (:left)
    #   The mouse button to click.
    #
    # @option options [Integer] :count (1)
    #
    # @option options [Integer] :modifiers
    #   Bitfield for key modifiers. See `keyboard.modifiers`.
    #   If omitted, uses the keys held by `keyboard.hold`, or none outside of it.
    #
    # @return [self]
    #
    # @raise [TimeoutError]
    #
    def click(x:, y:, delay: 0, navigation_wait: Page::NAVIGATION_WAIT, wait: nil, timeout: nil, **options) # rubocop:disable Metrics/ParameterLists
      navigation_wait = Utils::Deprecate.renamed_keyword(:wait, :navigation_wait, wait, navigation_wait)
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
    # @option options [:left, :right] :button (:left)
    #   The mouse button to click.
    #
    # @option options [Integer] :count (1)
    #
    # @option options [Integer] :modifiers
    #   Bitfield for key modifiers. See `keyboard.modifiers`.
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
    # @option options [:left, :right] :button (:left)
    #   The mouse button to click.
    #
    # @option options [Integer] :count (1)
    #
    # @option options [Integer] :modifiers
    #   Bitfield for key modifiers. See `keyboard.modifiers`.
    #   If omitted, uses the keys held by `keyboard.hold`, or none outside of it.
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
    # @param [Integer, nil] modifiers
    #   Bitfield for key modifiers. See `keyboard.modifiers`.
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
                        modifiers: modifiers || @page.keyboard.held_modifiers)
        end
      end

      self
    end

    private

    def mouse_event(type:, button: :left, count: 1, modifiers: nil, navigation_wait: 0, timeout: nil)
      button = validate_button(button)
      register_event_button(type, button)
      options = { x: @x, y: @y, type: type, button: button, buttons: @buttons, clickCount: count,
                  modifiers: modifiers || @page.keyboard.held_modifiers }
      return @page.command("Input.dispatchMouseEvent", slowmoable: true, **options) unless navigation_wait.positive?

      deadline = Deadline.wrap(timeout || @page.timeout)
      result = nil
      @page.wait_for_navigation!(navigation_wait, timeout: deadline) do
        result = @page.command("Input.dispatchMouseEvent", slowmoable: true, timeout: deadline, **options)
      end
      result
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
