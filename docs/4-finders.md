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

#### current_url : `String`

Returns current top window location href.

```ruby
page.go_to("https://google.com/")
page.current_url # => "https://www.google.com/"
```

#### current_title : `String`

Returns current top window title

```ruby
page.go_to("https://google.com/")
page.current_title # => "Google"
```

#### body : `String`

Returns current page's html.

```ruby
page.go_to("https://google.com/")
page.body # => '<html itemscope="" itemtype="http://schema.org/WebPage" lang="ru"><head>...
```
