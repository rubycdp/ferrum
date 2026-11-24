---
sidebar_position: 18
---

# Node

A DOM node found on a page or in a frame, by the [finders](https://github.com/rubycdp/ferrum#Finders). A node belongs to
the target it was found on, so one fetched before a navigation can't be used after it.

```ruby
node = page.at_css("input[name='q']") # => Node
```

#### page : `Page`
#### target_id : `String`
#### backend_node_id : `Integer`

The page the node belongs to, the id of its target and Chrome's id of the node, which stays the same for the node's
lifetime.

#### node_type : `Integer`

The DOM `nodeType`, `1` for an element and `3` for a text node.

#### tag_name : `String`

The lowercased tag name of an element, or the node name of any other node, e.g. `"#text"`.

```ruby
page.at_css("#nav").tag_name # => "div"
```

#### description : `Hash`

Chrome's description of the node from `DOM.describeNode`, fetched on first use.

```ruby
page.at_css("a").description["nodeName"] # => "A"
```

#### node? : `Boolean`

Whether this is an element node, as opposed to e.g. a text node.

```ruby
page.at_css("a").node? # => true
page.xpath("//a/text()").first.node? # => false
```

#### frame_id : `String` | `nil`

The id of the frame an `iframe` or `frame` element contains, `nil` for other nodes.

#### frame  : `Frame`

Returns [Frame](https://github.com/rubycdp/ferrum#frame) object for current node, you can keep using
[Finders](https://github.com/rubycdp/ferrum#Finders) for that object:

```ruby
frame =  page.at_xpath("//iframe").frame # => Frame
frame.at_css("//a[text() = 'Log in']") # => Node
```

#### focus : `Node`

Focuses the node.

```ruby
input = page.at_css("input[name='q']")
input.focus
```

#### focusable? : `Boolean`

Whether the node can receive focus. It tries to [focus](#focus) the node to find out, and leaves it focused when it can:

```ruby
page.at_css("input[type=hidden]").focusable? # => false
page.at_css("input[name='q']").focusable? # => true
```

#### wait_still(timeout: nil, interval: 0.01) : `Array<Array<Float>>` | `nil`

Polls the node's position until two snapshots taken `interval` seconds apart match, `click` does it before moving the
mouse. Returns the content quads of the node, each one the eight coordinates of its four corners, or `nil` if it keeps
moving for `timeout`, the page timeout by default. `wait_still!` raises `Ferrum::TimeoutError` instead.

```ruby
page.at_css("#modal").wait_still
# => [[50.2, 390.9, 203.2, 390.9, 203.2, 411.9, 50.2, 411.9]]
```

#### moving?(delay: `Float`) : `Boolean`

Whether the node's position changes within `delay` seconds, `0.05` by default or `FERRUM_NODE_MOVING_CHECK` when set. A
shorter delay can miss a node that moves slowly.

```ruby
page.at_css(".animated").moving? # => true
page.at_css("#nav").moving? # => false
```

#### blur : `Node`

Removes focus from the node.

```ruby
page.at_css("input[name='q']").focus.blur
```

#### type(\*keys, timeout: nil) : `Node`

Types the keys with the page's keyboard, into whatever is focused, so it's usually chained after `focus` or `click`. See
[keyboard](https://github.com/rubycdp/ferrum#keyboard) for what a key can be. `timeout` bounds typing all the keys together,
the page timeout by default.

```ruby
page.at_css("input[name='q']").focus.type("Ruby", :Enter)
```

#### click(\*\*options) : `Node`

Clicks the node at its center, or at an offset from it, by moving the mouse there first. Waits for the node to stop
moving.

* options `Hash`
  * :button `Symbol` `:left` | `:right` | `:middle` | `:back` | `:forward`, `:left` by default
  * :count `Integer` how many times to click, `1` by default, `2` is a double click
  * :modifiers `Array<Symbol>` modifiers to hold while clicking, `:alt`, `:ctrl` or `:control`, `:meta` or `:command`,
    `:shift`. If omitted, uses the keys held by `keyboard.hold`, or none outside of it
  * :offset `Hash` where to click instead of the center, needs both `:x` and `:y`
    * :x `Integer`
    * :y `Integer`
    * :position `Symbol` `:top` | `:center`, what the offset is measured from, the top-left corner of the node or its
      center, `:top` by default
  * :delay `Float` delay between mouse down and mouse up, `0` by default
  * :navigation_wait `Numeric` | `false` seconds to watch for a navigation started by a left click, then wait for it to
    load, `Page::NAVIGATION_WAIT` by default. Only a single left click waits. `false` returns right after the click.
  * :timeout `Numeric` how long finding the node's position, the click and the page load it starts may take together,
    the page timeout by default

```ruby
page.at_css("a").click
page.at_css("a").click(navigation_wait: false)
page.at_css("a").click(timeout: 30)
page.at_css("a").click(button: :right)
page.at_css("a").click(count: 2)
page.at_css("a").click(modifiers: [:ctrl, :shift])
page.at_css("canvas").click(offset: { x: 10, y: 20 })
page.at_css("canvas").click(offset: { x: 10, y: 20, position: :center })
```

#### hover(\*\*options) : `Node`

Moves the mouse over the node's center, or an offset from it, so it matches `:hover` and gets `mouseover`,
`mouseenter` and `mousemove`. Waits for the node to stop moving.

* options `Hash`
  * :offset `Hash` where to move instead of the center, same as for `click`
  * :timeout `Numeric` how long finding the node's position and moving there may take together, the page timeout by
    default

```ruby
menu = page.at_css("#menu").hover
menu.evaluate("this.matches(':hover')") # => true
```

#### scroll : `Node`

Scrolls the node into view if it isn't visible yet.

```ruby
page.at_css("#footer").scroll
```

#### in_viewport?(of: `Node` | `nil`) : `Boolean`

Whether the node is fully inside the viewport, or inside the bounds of the `of` node when it is given.

```ruby
page.at_css("#footer").in_viewport? # => false
page.at_css("#footer").scroll.in_viewport? # => true
page.at_css("#row").in_viewport?(of: page.at_css("#table")) # => true
```

#### select_file(value) : `Node`

Sets files on a file input.

* value `String` | `Array<String>` path or paths of the files

```ruby
page.at_css("input[type=file]").select_file("/path/to/file.png")
```

#### at_xpath(selector) : `Node` | `nil`
#### at_css(selector) : `Node` | `nil`
#### xpath(selector) : `Array<Node>`
#### css(selector) : `Array<Node>`

Finders that search within the node, in the frame the node belongs to.

```ruby
form = page.at_css("form")
form.at_css("input[name='q']") # => Node
form.at_xpath(".//input[@name='q']") # => Node
form.css("input") # => [Node, Node]
form.xpath(".//input") # => [Node, Node]
```

#### text : `String`

The text content of the node, i.e. `textContent`.

```ruby
page.at_css("a > h3").text # => "rubycdp/ferrum: Ruby Chrome/Chromium driver - GitHub"
```

#### inner_text : `String`

The rendered text of the node, i.e. `innerText`. Unlike `text` it follows the layout: text hidden by CSS is left out and
line breaks are kept.

```ruby
# <p>Hello <span style="display: none">hidden</span>world</p>
page.at_css("p").text # => "Hello hiddenworld"
page.at_css("p").inner_text # => "Hello world"
```

#### value : `Object`

The `value` property of the node, for form elements such as `input`, `select` and `textarea`.

```ruby
page.at_css("input[name='q']").value # => "ferrum"
```

#### property(name) : `Object`

The JavaScript property of the node.

* name `String`

```ruby
page.at_css("input").property("value") # => "Foo"
```

#### attribute(name) : `String` | `nil`

The HTML attribute of the node, i.e. `getAttribute(name)`. Unlike `property` it is what the markup says rather than the
live state of the node.

* name `String`

```ruby
page.at_css("input").attribute("value") # => "Foo"
```

#### selected : `Array<Node>`

The selected `option` nodes of a `select`, raises `Ferrum::JavaScriptError` for any other node.

```ruby
page.at_css("select#title").selected.map(&:text) # => ["Mrs"]
```

#### select(\*values, by: `Symbol`) : `Node`

(chainable) Selects options by passed attribute.

* values `String` | `Array<String>`
* by `Symbol` the attribute of the `option` to match, `:value` by default, or `:text`

```ruby
page.at_xpath("//*[select]").select(["1"]) # => Node (select)
page.at_xpath("//*[select]").select(["text"], by: :text) # => Node (select)
```

Accept string, array or strings:
```ruby
page.at_xpath("//*[select]").select("1")
page.at_xpath("//*[select]").select("1", "2")
page.at_xpath("//*[select]").select(["1", "2"])
```

#### evaluate(expression, \*positional, \*\*keywords) : `Object`
#### evaluate_handle(expression, \*positional, \*\*keywords) : `RemoteObject` | `Node` | `Object`
#### execute(expression, \*positional, \*\*keywords) : `Node`

Run JavaScript with `this` bound to the node. `evaluate` returns the result, `evaluate_handle` returns a handle that
stays in the browser instead of a serialized value (a `Node` for a node, the value itself for a primitive), `execute`
returns `true`. Arrow functions don't get `this`, use a `function` when the script needs it. The scripts and arguments
are the same as in [JavaScript](https://github.com/rubycdp/ferrum#javascript).

```ruby
page.at_css("input").evaluate("this.value")
page.at_css("input").evaluate("this.value + suffix", suffix: "!")
page.at_css("input").execute("this.value = text", text: "hello")
page.at_css("form").evaluate_handle("this.dataset") # => RemoteObject
page.at_css("form").evaluate_handle("this") # => Node
```

#### computed_style : `Hash`

The computed CSS styles of the node.

```ruby
page.at_css("a").computed_style["display"] # => "inline"
```

#### ax_node : `Accessibility::AXNode` | `nil`

The node in the accessibility tree, `nil` if it is ignored there. See
[accessibility](https://github.com/rubycdp/ferrum#accessibility).

```ruby
page.at_css("a").ax_node.role # => "link"
```

#### pinpoint(x: `Numeric`, y: `Numeric`, position: `Symbol`) : `Array<Float>`

The `[x, y]` point a click on the node would land on, in viewport coordinates, without clicking. `x` and `y` are an
offset from the node's center (`position: :center`, the default) or from its top-left corner (`position: :top`).
`click(offset:)` and `hover(offset:)` take the same keys.

```ruby
page.at_css("input").pinpoint # => [126.7, 401.4]
page.at_css("input").pinpoint(x: 5, y: 5) # => [131.7, 406.4]
page.at_css("input").pinpoint(x: 5, y: 5, position: :top) # => [55.2, 395.9]
```

#### remove : `Node`

Removes the node from the DOM.

```ruby
page.at_css("#ad").remove
```

#### exists? : `Boolean`

Whether the node is still in the DOM.

```ruby
node = page.at_css("#ad")
node.remove
node.exists? # => false
```

#### ==(other) : `Boolean`

Two nodes are equal when they belong to the same target and have the same backend node id, so the same element found
twice is equal to itself.

```ruby
page.at_css("a") == page.at_css("a") # => true
```
