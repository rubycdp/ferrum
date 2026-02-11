---
sidebar_position: 14
---

# Emulation

#### set_viewport

Overrides device screen dimensions and emulates viewport.

* options `Hash`
  * :width `Integer`, viewport width. `0` by default
  * :height `Integer`, viewport height. `0` by default
  * :scale_factor `Float`, device scale factor. `0` by default
  * :mobile `Boolean`, whether to emulate mobile device. `false` by default

```ruby
page.set_viewport(width: 1000, height: 600, scale_factor: 3)
```
