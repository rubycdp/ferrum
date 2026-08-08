---
sidebar_position: 17
---

# Animation

You can slow down or speed up CSS animations.

#### playback_rate : `Integer`

Returns playback rate for CSS animations, defaults to `1`.


#### playback_rate = value

Sets playback rate of CSS animations

* value `Integer`

```ruby
page.playback_rate = 2000
page.go_to("https://google.com")
page.playback_rate # => 2000
```
