---
sidebar_position: 14
---

# Emulation

#### set_viewport

Overrides device screen dimensions and emulates viewport. When `:mobile` is
`true`, this also enables touch emulation (`navigator.maxTouchPoints`,
`ontouchstart`) alongside the mobile viewport metrics.

* options `Hash`
  * :width `Integer`, viewport width. `0` by default
  * :height `Integer`, viewport height. `0` by default
  * :scale_factor `Float`, device scale factor. `0` by default
  * :mobile `Boolean`, whether to emulate mobile device and enable touch. `false` by default

```ruby
page.set_viewport(width: 1000, height: 600, scale_factor: 3)
```

`:width`, `:height`, and `:scale_factor` all default to `0`, which per the
[DevTools protocol](https://chromedevtools.github.io/devtools-protocol/tot/Emulation/#method-setDeviceMetricsOverride)
disables overriding that particular value. This means `mobile:` can be
enabled on its own, at the page's current size, without specifying a device
size preset:

```ruby
page.set_viewport(mobile: true)
```
