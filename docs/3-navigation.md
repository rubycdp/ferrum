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

#### wait_for_navigation(wait = 0.1) { } : `Boolean`

Runs the block and, if it starts a navigation within `wait` seconds, waits for the new page to load. Returns `false`
if it doesn't load within the page timeout. `click` already does this, use it for navigations started from
JavaScript.

* wait `Numeric` seconds to watch for a navigation after the block, `FERRUM_CLICK_WAIT` or `0.1` by default

```ruby
page.wait_for_navigation { page.at_css("a").evaluate("this.click()") } # => true
page.current_url # => the link's page
```

#### wait_for_navigation!(wait = 0.1) { }

Same as `wait_for_navigation`, but raises `Ferrum::TimeoutError` if the new page doesn't load within the page timeout.

```ruby
page.wait_for_navigation! { page.at_css("a").evaluate("this.click()") }
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
