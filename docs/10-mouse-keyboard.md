---
sidebar_position: 10
---

# Mouse & Keyboard

## Mouse

`page.mouse`

#### scroll_to(x, y)

Scroll page to a given x, y

* x `Integer` the pixel along the horizontal axis of the document that you
  want displayed in the upper left
* y `Integer` the pixel along the vertical axis of the document that you want
  displayed in the upper left

```ruby
page.go_to("https://www.google.com/search?q=Ruby+headless+driver+for+Capybara")
page.mouse.scroll_to(0, 400)
```

#### click(\*\*options) : `Mouse`

Click given coordinates, fires mouse move, down and up events.

* options `Hash`
    * :x `Integer`
    * :y `Integer`
    * :delay `Float` defaults to 0. Delay between mouse down and mouse up events
    * :button `Symbol` :left | :right, defaults to :left
    * :count `Integer` defaults to 1
    * :modifiers `Integer` bitfield for key modifiers. See `keyboard.modifiers`.
      If omitted, uses the keys held by `keyboard.hold`, or none outside of it

#### down(\*\*options) : `Mouse`

Mouse down for given coordinates.

* options `Hash`
    * :button `Symbol` :left | :right, defaults to :left
    * :count `Integer` defaults to 1
    * :modifiers `Integer` bitfield for key modifiers. See `keyboard.modifiers`.
      If omitted, uses the keys held by `keyboard.hold`, or none outside of it

#### up(\*\*options) : `Mouse`

Mouse up for given coordinates.

* options `Hash`
    * :button `Symbol` :left | :right, defaults to :left
    * :count `Integer` defaults to 1
    * :modifiers `Integer` bitfield for key modifiers. See `keyboard.modifiers`.
      If omitted, uses the keys held by `keyboard.hold`, or none outside of it

#### move(x:, y:, steps: 1, modifiers: nil) : `Mouse`

Mouse move to given x and y.

* options `Hash`
    * :x `Integer`
    * :y `Integer`
    * :steps `Integer` defaults to 1. Sends intermediate mousemove events.
    * :modifiers `Integer` bitfield for key modifiers. See `keyboard.modifiers`.
      If omitted, uses the keys held by `keyboard.hold`, or none outside of it

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

#### type(\*keys) : `Keyboard`

Sends a keydown, keypress/input, and keyup event for each character in the text.

* text `String` | `Array<String> | Array<Symbol>` A text to type into a focused
  element, `[:Shift, "s"], "tring"`

#### hold(\*keys) { } : `Object`

Holds modifier keys down while the block runs. Every keyboard and mouse event inside the block carries them, and they
are released when the block returns or raises. Returns the block's value.

* keys `Symbol` :alt | :ctrl | :control | :meta | :command | :shift

```ruby
page.keyboard.hold(:shift) do
  page.mouse.move(x: 10, y: 10).down.move(x: 200, y: 200, steps: 10).up
end
```

#### held_modifiers : `Integer`

Modifier keys currently pressed by `hold`, in the same format as `modifiers` returns. It's 0 outside a `hold` block.

```ruby
page.keyboard.hold(:shift) { page.keyboard.held_modifiers } # => 8
```

#### modifiers(keys) : `Integer`

Returns bitfield for a given keys

* keys `Array<Symbol>` :alt | :ctrl | :command | :shift

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
