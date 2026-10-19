---
sidebar_position: 13
---

# JavaScript

#### evaluate(expression, \*args, timeout: nil, \*\*named)

Evaluate JavaScript and return the result, converted to Ruby.

* expression `String` a JavaScript expression, or a function/arrow declaration, which is used as-is and is how you
  run more than one statement
* args positional arguments, reachable as `arguments[0]` and up. Can't be mixed with named ones
* timeout `Numeric` seconds to wait for the script and any promise it returns, defaults to the page timeout, `0`
  waits for as long as it takes. Raises `Ferrum::ScriptTimeoutError`, a `Ferrum::TimeoutError`, when exceeded
* named named arguments, which become the script's parameters. A `Ferrum::Node` arrives as the live element. Use
  `args: { timeout: 1 }` for a parameter named `timeout` or `args`

```ruby
page.evaluate("[window.scrollX, window.scrollY]") # => [0, 0]
page.evaluate("a + b", a: 1, b: 2) # => 3
page.evaluate("el.getAttribute(name)", el: page.at_css("a"), name: "href")
page.evaluate("await fetch(url).then(r => r.status)", url: "/") # => 200
page.evaluate(<<~JS, c: 3) # => 9
  function(c) {
    const sum = 1 + 2;
    return sum * c;
  }
JS
```

#### evaluate_handle(expression, \*args, timeout: nil, \*\*named) : `Ferrum::RemoteObject`

Same as `evaluate`, but keeps the value in the browser and returns a reference you can pass back in as an argument.
Call `#value` to convert it to Ruby, and `#release` to free it.

```ruby
list = page.evaluate_handle("document.querySelectorAll('li')")
page.evaluate("Array.from(nodes).map(n => n.textContent)", nodes: list)
```

#### execute(expression, \*args, timeout: nil, \*\*named) : `Boolean`

Run JavaScript for its side effects. The script is used as a function body, so statements need no wrapping.

```ruby
page.execute("window.scrollBy(0, 100)") # => true
```

`Ferrum::Node` has the same three methods, with `this` bound to the element. Arrow functions don't get `this`, so use a
`function` declaration when you need it.

```ruby
page.at_css("input").evaluate("this.value")
page.at_css("input").execute("this.value = text", text: "hello")
```

#### Upgrading to 0.21

0.21 finishes the move to the API above. Ferrum 0.20 runs old-style scripts as before and warns about each change below,
pointing at your code, so upgrade to 0.20 first and fix its warnings.

| Script | 0.20 | 0.21 | Rewrite |
|---|---|---|---|
| Keyword arguments read through `arguments` | one object in `arguments[0]` | named parameters | `evaluate("options.foo", options: { foo: 1 })` |
| Mixing positional and keyword arguments | keywords appended as an object | `ArgumentError` | pass the object in braces, or name every argument |
| More than one expression, `"a(); b"` | returns `a()`, skips the rest | `SyntaxError` | `evaluate("function() { a(); return b }")` |
| A line break before the script | `nil`, nothing runs | runs and returns its value | check it's safe to run, or remove it |
| Returns a promise | `{}`, not awaited | awaited, raises if rejected | prefix with `void` to keep it from waiting |
| Returns an object with a `then` method | the object | awaited like a promise | wrap it, `({ value: object })` |
| Throws something that isn't an `Error` | the thrown value | `Ferrum::JavaScriptError` | return the value instead |
| `Node#evaluate` returns a node, nodes or a `Date` | `{}` | `Ferrum::Node`, or the date's string | check the code using the result |
| `evaluate_async(expression, wait, *args)` | deprecated | removed | `evaluate("await …", timeout: wait)` |
| `evaluate_func(function, *args, on:)` | deprecated | removed | `evaluate(function, a: 1)`, or `node.evaluate(function)` |
| `evaluate_on(node:, expression:)` | deprecated | removed | `node.evaluate(expression)` |

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
scripts can't see or override what runs there. It has `evaluate`, `evaluate_handle` and `execute`,
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
