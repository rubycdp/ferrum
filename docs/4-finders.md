---
sidebar_position: 4
---

# Finders

#### at_css(selector, \*\*options) : `Node` | `nil`

Find node by selector. Runs `document.querySelector` within the document or
provided node.

* selector `String`
* options `Hash`
  * :within `Node` | `nil`

```ruby
page.go_to("https://github.com/")
page.at_css("a[aria-label='Issues you created']") # => Node
```

#### css(selector, \*\*options) : `Array<Node>` | `[]`

Find nodes by selector. The method runs `document.querySelectorAll` within the
document or provided node.

* selector `String`
* options `Hash`
  * :within `Node` | `nil`

```ruby
page.go_to("https://github.com/")
page.css("a[aria-label='Issues you created']") # => [Node]
```

#### at_xpath(selector, \*\*options) : `Node` | `nil`

Find node by xpath.

* selector `String`
* options `Hash`
  * :within `Node` | `nil`

```ruby
page.go_to("https://github.com/")
page.at_xpath("//a[@aria-label='Issues you created']") # => Node
```

#### xpath(selector, \*\*options) : `Array<Node>` | `[]`

Find nodes by xpath.

* selector `String`
* options `Hash`
  * :within `Node` | `nil`

```ruby
page.go_to("https://github.com/")
page.xpath("//a[@aria-label='Issues you created']") # => [Node]
```

#### wait_css(selector, \*\*options) : `Node` | `nil`

#### wait_xpath(selector, \*\*options) : `Node` | `nil`

Polls `at_css` or `at_xpath` until a node matches the selector and returns it, or `nil` if none does within
`timeout`. `wait_css!` and `wait_xpath!` raise `Ferrum::TimeoutError` instead.

* selector `String`
* options `Hash`
  * :within `Node` | `nil`
  * :timeout `Numeric` how long to keep trying, the page timeout by default
  * :interval `Numeric` seconds to sleep between attempts, `0.05` by default

```ruby
page.go_to("https://github.com/")
page.wait_css("a[aria-label='Issues you created']") # => Node
page.wait_xpath!("//a[@aria-label='Issues you created']") # => Node
```

#### url : `String`

Returns the page's location href. On a frame `url` is that frame's own, see [Frames](/docs/ferrum/frames).

```ruby
page.go_to("https://google.com/")
page.url # => "https://www.google.com/"
```

#### title : `String`

Returns the page's title.

```ruby
page.go_to("https://google.com/")
page.title # => "Google"
```

`current_url` and `current_title` are deprecated and will be removed in 0.22, use `url` and `title`.

#### html : `String`

Returns the HTML of the whole document, `<html>` included. `body` is deprecated and will be removed in 0.22, it never
returned only `<body>`.

```ruby
page.go_to("https://google.com/")
page.html # => '<html itemscope="" itemtype="http://schema.org/WebPage" lang="ru"><head>...
```
