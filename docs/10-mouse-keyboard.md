---
sidebar_position: 10
---

# Mouse & Keyboard

## Mouse

`page.mouse`

#### scroll_by(x: 0, y: 0) : `Mouse`

Scrolls the page by the given amount, instantly even when the page sets `scroll-behavior: smooth`.

* x `Integer` the horizontal pixels to scroll by
* y `Integer` the vertical pixels to scroll by

```ruby
page.mouse.scroll_by(y: 400)
```

#### scroll_to(x: nil, y: nil) : `Mouse`

Scrolls the page to the given coordinates, instantly even when the page sets `scroll-behavior: smooth`.

* x `Integer` the pixel along the horizontal axis of the document to show in the upper left, the current one if
  omitted
* y `Integer` the pixel along the vertical axis of the document to show in the upper left, the current one if
  omitted

```ruby
page.go_to("https://www.google.com/search?q=Ruby+headless+driver+for+Capybara")
page.mouse.scroll_to(x: 0, y: 400)
page.mouse.scroll_to(y: 0)
```

#### click(\*\*options) : `Mouse`

Click given coordinates, fires mouse move, down and up events.

* options `Hash`
    * :x `Integer`
    * :y `Integer`
    * :delay `Float` defaults to 0. Delay between mouse down and mouse up events
    * :navigation_wait `Numeric` | `false` defaults to `Page::NAVIGATION_WAIT`. Seconds to watch for a navigation started
      by the click, then wait for it to load. `false` returns right after the click.
    * :timeout `Numeric` how long the click and the page load it starts may take together, the page timeout by default
    * :button `Symbol` :left | :right | :middle | :back | :forward, defaults to :left
    * :count `Integer` defaults to 1
    * :modifiers `Array<Symbol>` | `Integer` modifier keys to hold, `:alt`, `:ctrl` or `:control`, `:meta` or
      `:command`, `:shift`, or CDP's `modifiers` bitfield. If omitted, uses the keys held by `keyboard.hold`, or
      none outside of it

#### down(\*\*options) : `Mouse`

Mouse down for given coordinates.

* options `Hash`
    * :button `Symbol` :left | :right | :middle | :back | :forward, defaults to :left
    * :count `Integer` defaults to 1
    * :modifiers `Array<Symbol>` | `Integer` modifier keys to hold, `:alt`, `:ctrl` or `:control`, `:meta` or
      `:command`, `:shift`, or CDP's `modifiers` bitfield. If omitted, uses the keys held by `keyboard.hold`, or
      none outside of it

#### up(\*\*options) : `Mouse`

Mouse up for given coordinates.

* options `Hash`
    * :button `Symbol` :left | :right | :middle | :back | :forward, defaults to :left
    * :count `Integer` defaults to 1
    * :modifiers `Array<Symbol>` | `Integer` modifier keys to hold, `:alt`, `:ctrl` or `:control`, `:meta` or
      `:command`, `:shift`, or CDP's `modifiers` bitfield. If omitted, uses the keys held by `keyboard.hold`, or
      none outside of it
    * :navigation_wait `Numeric` | `false` seconds to watch for a navigation started by releasing the button, then
      wait for it to load, defaults to `false`
    * :timeout `Numeric` how long the event and the page load it starts may take together, the page timeout by default

#### move(x:, y:, steps: 1, modifiers: nil, timeout: nil) : `Mouse`

Mouse move to given x and y.

* options `Hash`
    * :x `Integer`
    * :y `Integer`
    * :steps `Integer` defaults to 1. Sends intermediate mousemove events.
    * :modifiers `Array<Symbol>` | `Integer` modifier keys to hold, `:alt`, `:ctrl` or `:control`, `:meta` or
      `:command`, `:shift`, or CDP's `modifiers` bitfield. If omitted, uses the keys held by `keyboard.hold`, or
      none outside of it
    * :timeout `Numeric` how long all the steps may take together, the page timeout by default

## Keyboard

`page.keyboard`

#### down(key) : `Keyboard`

Dispatches a keydown event.

* key `String` | `Symbol` Name of key such as "a", :enter, :backspace. Raises `ArgumentError` for a modifier,
  use `hold` instead

#### up(key) : `Keyboard`

Dispatches a keyup event.

* key `String` | `Symbol` Name of key such as "b", :enter, :backspace. Raises `ArgumentError` for a modifier,
  use `hold` instead

#### type(\*keys, timeout: nil) : `Keyboard`

Sends a keydown, keypress/input, and keyup event for each character in the text.

* text `String` | `Array<String> | Array<Symbol>` A text to type into a focused
  element, `[:Shift, "s"], "tring"`
* timeout `Numeric` how long typing all the keys may take together, the page timeout by default. Raise it for a long
  text

#### hold(\*keys) { } : `Object`

Holds modifier keys down while the block runs. Every keyboard and mouse event inside the block carries them, and they
are released when the block returns or raises. Returns the block's value.

* keys `Symbol` :alt | :ctrl | :control | :meta | :command | :shift

```ruby
page.keyboard.hold(:shift) do
  page.mouse.move(x: 10, y: 10).down.move(x: 200, y: 200, steps: 10).up
end
```

## Examples

```ruby
# Type text into an input
page.go_to("https://google.com")
input = page.at_css("input[name='q']")
input.focus
page.keyboard.type("Hello World")

# Press Enter
page.keyboard.type(:Enter)

# Use keyboard shortcuts
page.keyboard.hold(:shift) { page.keyboard.type("hello") }
```
