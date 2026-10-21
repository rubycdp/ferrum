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

#### evaluate_on_new_document(source, \*\*options) : `String`

Runs JavaScript in every new document of the page and its in-process frames, before the document's own scripts.
Returns the script identifier. For every page and iframe of the browser, use `add_extension`.

* source `String` should be valid JavaScript
* options `Hash`
  * :world_name `String` - run in an isolated world with this name instead of the page's main world
  * :run_immediately `Boolean` - run in the current document as well, `false` by default

```ruby
id = page.evaluate_on_new_document <<~JS
  Object.defineProperty(navigator, "languages", {
    get: function() { return ["tlh"]; }
  });
JS
```

#### isolated_world(name) : `IsolatedWorld`

Returns the frame's isolated world with this name, its own JavaScript globals over the frame's DOM, so the page's
scripts can't see or override what runs there. It has `evaluate`, `evaluate_async`, `execute` and `evaluate_func`,
takes and returns nodes, and comes back empty in every new document. On a page it's the main frame's world, use
`frame.isolated_world(name)` for an iframe. It's the same world `evaluate_on_new_document` runs in with
`world_name:`.

* name `String`

```ruby
world = page.isolated_world("ferrum")
world.execute("window.secret = 'top'")
world.evaluate("window.secret") # => "top"
page.evaluate("window.secret") # => nil
world.evaluate("document.title") # => same as page.evaluate("document.title")
```

#### remove_script_on_new_document(identifier) : `Boolean`

Stops running a script added with `evaluate_on_new_document` in new documents.

```ruby
page.remove_script_on_new_document(id) # => true
```

#### add_extension(extension)

Adds an extension, see the `:extensions` option. It runs in every page and iframe, popups and out-of-process iframes
included, attached after the call, before their own scripts. Pages already open keep the extensions they had.

* extension `String | Hash` a path to a JS file or `{ source: "..." }`

```ruby
browser.add_extension("/path/to/stub.js")
browser.add_extension(source: "window.secret = 'top'")
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

## Console

#### console : `Console`

What the DevTools console would show for the page: `console.*` calls, browser log entries (failed resource loads,
CSP violations, deprecations, ...) and uncaught exceptions. It keeps the last 1000 messages, oldest first, and is
`Enumerable`, so filter it like any collection.

```ruby
page.go_to("https://example.com")
page.console.select(&:error?) # => [#<Ferrum::Console::Message type=:error source=:network ...>]
page.console.select { |message| message.match?(/deprecated/) }
page.console.last.text # => "Hello world"
page.console.clear
```

`Ferrum::Console::Message` has:

* `type` `Symbol` - `:log`, `:info`, `:warning`, `:error`, `:debug`, `:table`, ... for `console.*` calls, the log
  entry's level for browser log entries, `:error` for uncaught exceptions
* `source` `Symbol` - `:console_api`, `:exception`, or the log entry's source such as `:network` or `:security`
* `text` `String` - the arguments joined by spaces, objects and arrays as JSON
* `args` `Array` - the `console.*` arguments as Ruby values, objects and arrays built from Chrome's shallow preview
* `location` `Location` and `stack_trace` `Array<Location>` - `url`, `line`, `column`, `function_name`
* `timestamp` `Time`
* `severity` `Symbol` - `:debug`, `:info`, `:warn` or `:error`, the matching `Logger` method
* `error?`, `warning?`, `match?(pattern)`

#### on(:console)

Calls the block for every new message.

```ruby
logger = Logger.new($stdout)
page.on(:console) { |message| logger.public_send(message.severity, message.to_s) }
```

Fail a test on browser errors:

```ruby
after { expect(browser.console.select(&:error?)).to be_empty }
```
