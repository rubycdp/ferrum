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
    * :modifiers `Integer` bitfield for key modifiers. See`keyboard.modifiers`

#### down(\*\*options) : `Mouse`

Mouse down for given coordinates.

* options `Hash`
    * :button `Symbol` :left | :right, defaults to :left
    * :count `Integer` defaults to 1
    * :modifiers `Integer` bitfield for key modifiers. See`keyboard.modifiers`

#### up(\*\*options) : `Mouse`

Mouse up for given coordinates.

* options `Hash`
    * :button `Symbol` :left | :right, defaults to :left
    * :count `Integer` defaults to 1
    * :modifiers `Integer` bitfield for key modifiers. See`keyboard.modifiers`

#### move(x:, y:, steps: 1) : `Mouse`

Mouse move to given x and y.

* options `Hash`
    * :x `Integer`
    * :y `Integer`
    * :steps `Integer` defaults to 1. Sends intermediate mousemove events.

## Keyboard

`page.keyboard`

#### down(key) : `Keyboard`

Dispatches a keydown event.

* key `String` | `Symbol` Name of key such as "a", :enter, :backspace

#### up(key) : `Keyboard`

Dispatches a keyup event.

* key `String` | `Symbol` Name of key such as "b", :enter, :backspace

#### type(\*keys) : `Keyboard`

Sends a keydown, keypress/input, and keyup event for each character in the text.

* text `String` | `Array<String> | Array<Symbol>` A text to type into a focused
  element, `[:Shift, "s"], "tring"`

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
page.keyboard.down(:Shift)
page.keyboard.type("h", "e", "l", "l", "o")
page.keyboard.up(:Shift)
```
