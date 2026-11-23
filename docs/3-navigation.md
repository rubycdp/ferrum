---
sidebar_position: 4
---

# Navigation

Every method that waits for a page to load returns `nil` when it doesn't load in time, and has a `!` version that
raises `Ferrum::NavigationTimeoutError` instead, naming the requests still pending.

#### go_to(url, \*\*options) : `String` | `nil`

Navigate page to. Returns the navigated frame's id, or `nil` when the page doesn't load in time. It raises once an
enclosing `Ferrum::Deadline.within` has run out.

* url `String` The url should include scheme unless you set `base_url` when
  configuring driver.
* options `Hash`
  * :timeout `Numeric` How long the whole navigation may take, sending the request and loading the page together,
    the page timeout by default.
  * :referrer `String` The referrer of this navigation only: the document request sends it as `Referer` and
    `document.referrer` returns it, the page's other requests don't carry it. A `Referer` set with `headers` is sent
    with every request and takes its place.

```ruby
page.go_to("https://github.com/")
page.go_to("https://github.com/", timeout: 10)
page.go_to("https://github.com/", referrer: "https://google.com/")
```

#### go_to!(url, \*\*options) : `String`

Same as `go_to`, but raises `Ferrum::NavigationTimeoutError` if the page doesn't load in time.

```ruby
page.go_to!("https://github.com/")
```

#### back(timeout: nil) : `true` | `nil`

Navigate to the previous page in history. Returns `nil` when there's no previous page or it doesn't load in time,
`back!` raises in the latter case.

* timeout `Numeric` how long the history lookup and the page load may take together, the page timeout by default

```ruby
page.go_to("https://github.com/")
page.at_xpath("//a").click
page.back
page.back!(timeout: 10)
```

#### forward(timeout: nil) : `true` | `nil`

Navigate to the next page in history. Returns `nil` when there's no next page or it doesn't load in time,
`forward!` raises in the latter case.

* timeout `Numeric` how long the history lookup and the page load may take together, the page timeout by default

```ruby
page.go_to("https://github.com/")
page.at_xpath("//a").click
page.back
page.forward
```

#### refresh(timeout: nil) : `true` | `nil`

Reload current page. Returns `nil` when it doesn't load in time, `refresh!` raises instead.

* timeout `Numeric` how long the whole reload may take, the page timeout by default

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

#### await_navigation(watch: nil, timeout: nil) { } : `true` | `nil`

Runs the block and waits for the navigation it starts to load, e.g. a click on a link made from JavaScript. Returns
`nil` if no page loads within `timeout`. `click` already does this.

* watch `Numeric` seconds to watch for a navigation after the block, for code that may or may not navigate. When none
  begins in that time it returns `true` right away. By default a navigation must happen within `timeout`.
* timeout `Numeric` how long the block and the navigation may take together, the page timeout by default

```ruby
page.await_navigation { page.at_css("a").evaluate("this.click()") } # => true
page.url # => the link's page
page.await_navigation(watch: 0.1) { page.at_css("button").evaluate("this.click()") } # => true
```

#### await_navigation!(watch: nil, timeout: nil) { } : `true`

Same as `await_navigation`, but raises `Ferrum::TimeoutError` if the page doesn't load within `timeout`.

```ruby
page.await_navigation! { page.at_css("a").evaluate("this.click()") }
```

#### wait_until(timeout: nil, interval: 0.05) { } : `Object` | `nil`

Runs the block until it returns a truthy value and returns it, or `nil` if it doesn't within `timeout`, the page
timeout by default. `wait_until!` raises `Ferrum::TimeoutError` instead.

```ruby
page.wait_until { page.evaluate("window.ready") } # => true
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

#### await_page(\*\*options) { } : `Page` | `nil`

Runs the block and returns the page it opens, in a tab or a window, e.g. through `window.open` or a link with
`target="_blank"`. Returns `nil` if no page opens in time.

* options `Hash`
  * :opener `Page` only return a page opened by this page, by default a page opened by any page of the context
  * :timeout `Numeric` how long the block and the new page may take together, the browser's `timeout` by default

```ruby
opened = browser.await_page { browser.at_css("a[target=_blank]").click }
opened.url # => "https://example.com/"
opened.close

page = browser.create_page
opened = browser.await_page(opener: page) { page.at_css("a[target=_blank]").click }
```

#### await_page!(\*\*options) { } : `Page`

Same as `await_page`, but raises `Ferrum::TimeoutError` if no page opens in time.

Both only see a page that another page opened, through `window.open` or a link with `target="_blank"`, with or
without `noopener`. Chrome reports no opener for a page the user opens from a link: a click with Ctrl, Cmd or Shift
held, or a middle click. Such a page is not returned, compare the targets before and after the click instead:

```ruby
known = browser.targets.keys
browser.at_css("a").click(modifiers: [:ctrl]) # :meta on macOS
browser.pages { |t| !known.include?(t.id) } # => [#<Ferrum::Page>]
```

The target of an opened page has the id of the page that opened it:

```ruby
browser.targets[opened.target_id].opener_id == page.target_id # => true
```

#### pages { |target| } : `Array<Page>`

Returns the pages of the default context. With a block, only the pages of the targets it returns truthy for.

```ruby
browser.pages # => [#<Ferrum::Page>, #<Ferrum::Page>]
browser.pages(&:opener_id) # the pages opened by another page
browser.pages { |t| t.opener_id == page.target_id } # the pages opened by `page`
```
