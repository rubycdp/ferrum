---
sidebar_position: 4
---

# Navigation

#### go_to(url) : `String`

Navigate page to.

* url `String` The url should include scheme unless you set `base_url` when
  configuring driver.

```ruby
page.go_to("https://github.com/")
```

#### back

Navigate to the previous page in history.

```ruby
page.go_to("https://github.com/")
page.at_xpath("//a").click
page.back
```

#### forward

Navigate to the next page in history.

```ruby
page.go_to("https://github.com/")
page.at_xpath("//a").click
page.back
page.forward
```

#### refresh

Reload current page.

```ruby
page.go_to("https://github.com/")
page.refresh
```

#### stop

Stop all navigations and loading pending resources on the page

```ruby
page.go_to("https://github.com/")
page.stop
```

#### position = \*\*options

Set the position for the browser window

* options `Hash`
  * :left `Integer`
  * :top `Integer`

```ruby
browser.position = { left: 10, top: 20 }
```

#### position : `Array<Integer>`

Get the position for the browser window

```ruby
browser.position # => [10, 20]
```

#### window_bounds = \*\*options

Set window bounds

* options `Hash`
  * :left `Integer`
  * :top `Integer`
  * :width `Integer`
  * :height `Integer`
  * :window_state `String`

```ruby
browser.window_bounds = { left: 10, top: 20, width: 1024, height: 768, window_state: "normal" }
```

#### window_bounds : `Hash<String, Integer | String>`

Get window bounds

```ruby
browser.window_bounds # => { "left": 0, "top": 1286, "width": 10, "height": 10, "windowState": "normal" }
```

#### window_id : `Integer`

Current window id

```ruby
browser.window_id # => 1
```
