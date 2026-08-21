---
sidebar_position: 20
---

# Accessibility

Ferrum wraps the CDP [Accessibility](https://chromedevtools.github.io/devtools-protocol/tot/Accessibility/) domain,
letting you read the accessibility (AX) tree that assistive technologies (like screen readers) rely on. The query
methods below work without calling `enable` first; `enable`/`disable` exist only if you want live AX events.

`page.accessibility` returns the `Ferrum::Accessibility` instance for a page.

:::note
The node-scoped methods (`node_for`, `partial_tree`, and `query` with a `node:`) issue their command against the
node's owning page session. They support same-process (same-target) iframes; nodes living in an out-of-process
iframe (OOPIF, a separate CDP target) are not resolvable and will error or return an empty result.
:::

#### node_for(node) : `AXNode | nil`

Returns the single non-ignored `AXNode` for a DOM node, or `nil`.

* node `Ferrum::Node`

```ruby
node = page.at_css("button")
page.accessibility.node_for(node) # => #<Ferrum::Accessibility::AXNode ...>
```

You can also get to it directly from the node itself:

#### axnode : `AXNode | nil`

`Node#axnode` is a shortcut for `page.accessibility.node_for(self)`.

```ruby
page.at_css("button").axnode.role # => "button"
```

#### partial_tree(\*\*options) : `Array[AXNode]`

Returns the partial AX tree for a DOM node.

* options `Hash`
    * :node `Ferrum::Node` **required**
    * :fetch_relatives `Boolean` whether to include related nodes, `false` by default

```ruby
node = page.at_css("form")
page.accessibility.partial_tree(node: node)
```

#### snapshot(\*\*options) : `Array[AXNode]`

Returns the full AX tree for the page.

* options `Hash`
    * :depth `Integer` how many levels deep to fetch, unlimited by default
    * :frame_id `String` restrict the snapshot to a given frame

```ruby
page.accessibility.snapshot
```

#### root(\*\*options) : `AXNode | nil`

Returns the root `AXNode` of the (optionally framed) document.

* options `Hash`
    * :frame_id `String` restrict to a given frame

```ruby
page.accessibility.root
```

#### query(\*\*options) : `Array[AXNode]`

Query the AX tree by accessible name and/or role.

* options `Hash`
    * :name `String` accessible name to match
    * :role `String` AX role to match, e.g. `"button"`
    * :node `Ferrum::Node` scope the query to this node's subtree, whole page by default

```ruby
page.accessibility.query(role: "button")
page.accessibility.query(name: "Submit", role: "button")
```

#### enable : `self`
#### disable : `self`

Enable/disable the CDP Accessibility domain, only needed if you want live AX events; the query methods above work
without it.

## AXNode

Represents a single [AXNode](https://chromedevtools.github.io/devtools-protocol/tot/Accessibility/#type-AXNode)
from the CDP Accessibility domain. Instances are returned by the methods above, never constructed directly.

#### role : `String | nil`

The AX role, e.g. `"button"`, `"heading"`.

#### name : `String | nil`

The accessible name.

#### description : `String | nil`

The accessible description.

#### value : `String | Numeric | Boolean | nil`

The raw CDP `AXValue#value`; type varies by control (e.g. a checkbox's value is a boolean).

#### properties : `Hash`

ARIA/computed properties flattened to `name => value`, e.g. `{"focusable" => true}`.

#### ignored? : `Boolean`

Whether the node is ignored by the accessibility tree.

#### ignored_reasons : `Array | nil`

Why the node is ignored, if it is.

#### node_id : `String | nil`
#### backend_dom_node_id : `Integer | nil`
#### child_ids : `Array | nil`

Ids linking the AX node back to its DOM node and children in the AX tree.

#### to_h : `Hash`

The raw CDP AXNode hash.
