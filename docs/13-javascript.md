---
sidebar_position: 13
---

# JavaScript

#### evaluate(expression, \*args)

Evaluate and return result for given JS expression

* expression `String` should be valid JavaScript
* args `Object` you can pass arguments, though it should be a valid `Node` or a
  simple value.

```ruby
page.evaluate("[window.scrollX, window.scrollY]")
```

#### evaluate_async(expression, wait_time, \*args)

Evaluate asynchronous expression and return result

* expression `String` should be valid JavaScript
* wait_time How long we should wait for Promise to resolve or reject
* args `Object` you can pass arguments, though it should be a valid `Node` or a
  simple value.

```ruby
page.evaluate_async(%(arguments[0]({foo: "bar"})), 5) # => { "foo" => "bar" }
```

#### execute(expression, \*args)

Execute expression. Doesn't return the result

* expression `String` should be valid JavaScript
* args `Object` you can pass arguments, though it should be a valid `Node` or a
  simple value.

```ruby
page.execute(%(1 + 1)) # => true
```

#### evaluate_on_new_document(expression)

Evaluate JavaScript to modify things before a page load

* expression `String` should be valid JavaScript

```ruby
browser.evaluate_on_new_document <<~JS
  Object.defineProperty(navigator, "languages", {
    get: function() { return ["tlh"]; }
  });
JS
```

#### add_script_tag(\*\*options) : `Boolean`

* options `Hash`
  * :url `String`
  * :path `String`
  * :content `String`
  * :type `String` - `text/javascript` by default

```ruby
page.add_script_tag(url: "http://example.com/stylesheet.css") # => true
```

#### add_style_tag(\*\*options) : `Boolean`

* options `Hash`
  * :url `String`
  * :path `String`
  * :content `String`

```ruby
page.add_style_tag(content: "h1 { font-size: 40px; }") # => true

```
#### bypass_csp(\*\*options) : `Boolean`

* options `Hash`
  * :enabled `Boolean`, `true` by default

```ruby
page.bypass_csp # => true
page.go_to("https://github.com/ruby-concurrency/concurrent-ruby/blob/master/docs-source/promises.in.md")
page.refresh
page.add_script_tag(content: "window.__injected = 42")
page.evaluate("window.__injected") # => 42
```

#### disable_javascript

Disables Javascripts from the loaded HTML source.
You can still evaluate JavaScript with `evaluate` or `execute`.
Returns nothing.

```ruby
page.disable_javascript
```
