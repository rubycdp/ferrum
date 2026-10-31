---
sidebar_position: 18
---

# Node

#### node? : `Boolean`
#### frame_id
#### frame  : `Frame`

Returns [Frame](https://github.com/rubycdp/ferrum#frame) object for current node, you can keep using
[Finders](https://github.com/rubycdp/ferrum#Finders) for that object:

```ruby
frame =  page.at_xpath("//iframe").frame # => Frame
frame.at_css("//a[text() = 'Log in']") # => Node
```

#### focus
#### focusable? : `Boolean`

Whether the node can receive focus. It focuses the node to find out and then gives focus back to the element that had
it, so `focus`/`blur` (and `focusin`/`focusout`) events fire on both:

```ruby
page.at_css("input[type=hidden]").focusable? # => false
page.at_css("input[name='q']").focusable? # => true
```

#### moving?(delay: `Float`) : `Boolean`

Whether the node's position changes within `delay` seconds, `0.05` by default. A shorter delay can miss a node that
moves slowly.

#### wait_for_stop_moving
#### blur
#### type
#### click
#### hover
#### select_file
#### at_xpath
#### at_css
#### xpath
#### css
#### text
#### inner_text
#### value
#### property
#### attribute
#### evaluate
#### selected : `Array<Node>`
#### select
#### scroll_into_view
#### in_viewport?(of: `Node | nil`) : `Boolean`
#### remove
#### exists?

(chainable) Selects options by passed attribute.

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
