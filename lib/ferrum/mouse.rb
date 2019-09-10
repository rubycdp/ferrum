# frozen_string_literal: true

module Ferrum
  class Mouse
    CLICK_WAIT = ENV.fetch("FERRUM_CLICK_WAIT", 0.1).to_f
    VALID_BUTTONS = %w[none left middle right back forward].freeze

    def initialize(page)
      @page = page
      @x = @y = 0
    end

    def scroll_to(top, left)
      tap { @page.execute("window.scrollTo(#{top}, #{left})") }
    end

    def click(x:, y:, delay: 0, wait: CLICK_WAIT, **options)
      move(x: x, y: y)
      down(**options)
      sleep(delay)
      # Potential wait because if some network event is triggered then we have
      # to wait until it's over and frame is loaded or failed to load.
      up(wait: wait, **options)
      self
    end

    def down(**options)
      tap { mouse_event(type: "mousePressed", **options) }
    end

    def up(**options)
      tap { mouse_event(type: "mouseReleased", **options) }
    end

    # FIXME: steps
    def move(x:, y:, steps: 1)
      @x, @y = x, y
      @page.command("Input.dispatchMouseEvent", type: "mouseMoved", x: @x, y: @y)
      self
    end

    private

    def mouse_event(type:, button: :left, count: 1, modifiers: nil, wait: 0)
      button = validate_button(button)
      options = { x: @x, y: @y, type: type, button: button, clickCount: count }
      options.merge!(modifiers: modifiers) if modifiers
      @page.command("Input.dispatchMouseEvent", wait: wait, **options)
    end

    def validate_button(button)
      button = button.to_s
      unless VALID_BUTTONS.include?(button)
        raise "Invalid button: #{button}"
      end
      button
    end
  end
end
