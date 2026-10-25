---
sidebar_position: 13
---

# JavaScript

#### evaluate(expression, \*args, timeout: nil, \*\*named)

Evaluate JavaScript and return the result, converted to Ruby.

* expression `String` JavaScript returning the value of its last statement, or a function/arrow declaration, which
  is used as-is
* args positional arguments, a declaration's parameters or `arguments[0]` and up. Can't be mixed with named ones
* timeout `Numeric` seconds to wait for the script and any promise it returns, defaults to the page timeout. Raises
  `Ferrum::ScriptTimeoutError` when exceeded, which inherits from `Ferrum::TimeoutError`
* named named arguments, which become the parameters of a script that isn't a declaration. A `Ferrum::Node` arrives
  as the live element, but can't be put inside an Array or Hash. `timeout` can't be a parameter name

```ruby
page.evaluate("[window.scrollX, window.scrollY]") # => [0, 0]
page.evaluate("a + b", a: 1, b: 2) # => 3
page.evaluate("el.getAttribute(name)", el: page.at_css("a"), name: "href")
page.evaluate("await fetch(url).then(r => r.status)", url: "/") # => 200
page.evaluate(<<~JS, 3) # => 9
  function(c) {
    const sum = 1 + 2;
    return sum * c;
  }
JS
```

The result is converted to Ruby: objects become `Hash`, arrays and node lists `Array`, DOM nodes `Ferrum::Node`,
dates ISO 8601 strings, `NaN` and `Infinity` `Float`, `BigInt` `Integer`, `null` and `undefined` `nil`. Values
without a Ruby counterpart, such as functions, `Map`, `Set` or `window`, become `{}`. A reference back to an
enclosing object, e.g. `a.self = a`, becomes `Ferrum::CyclicObject`.

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

Scripts written for the old API run exactly as before, and Ferrum warns, pointing at your code, about any whose result
will change. Calls that only the new API can make, e.g. with named arguments, already run the new way.

* 0.20 runs old-style scripts the old way and warns. Set `FERRUM_JS_API=new` to run everything the new way.
* 0.21 removes the old way, along with `evaluate_async`, `evaluate_func` and `evaluate_on`. There's no switch back.

Warnings only cover the scripts and results your suite actually runs into, so before upgrading to 0.21, run the suite
once with `FERRUM_JS_API=new`. Set `FERRUM_DEPRECATION_WARNINGS=raise` to turn the warnings into errors while
migrating, or `0` to silence them. A library built on Ferrum should pass named arguments or a function declaration,
which run the new way in both 0.20 and 0.21.

| Script | < 0.21 | >= 0.21 | Notes |
|---|---|---|---|
| `evaluate("arguments[0].foo", foo: 1)` | `1` | `nil` | keywords are named parameters now, write `evaluate("foo", foo: 1)` |
| `evaluate("[arguments[0], arguments[1]]", 1, foo: 2)` | `[1, { "foo" => 2 }]` | `ArgumentError` | positional and keyword arguments can't be mixed, pass `{ foo: 2 }` in braces |
| `evaluate("a(); b")` | `a()`'s value, `b` never runs | `b`'s value | every statement runs, the last one's value is returned |
| `evaluate("\n  window.ran = true\n")` | `nil`, nothing runs | `true` | the line break no longer ends the `return`, check it's safe to run |
| `evaluate("Promise.resolve(1)")` | `{}` | `1` | promises are awaited, `void` keeps one from being awaited |
| `node.evaluate("this.parentNode")` | `{}` | `Ferrum::Node` | |
| `node.evaluate("new Date(0)")` | `{}` | `"1970-01-01T00:00:00.000Z"` | |
| `evaluate_async("arguments[0](1)", 5)` | `1` | `NoMethodError` | `evaluate("await …", timeout: 5)` |
| `evaluate_func("function(a) { return a }", 1)` | `1` | `NoMethodError` | `evaluate("function(a) { return a }", 1)`, with `on:` use `node.evaluate` |
| `evaluate_on(node: node, expression: "this.id")` | `"main"` | `NoMethodError` | `node.evaluate("this.id")` |
| `evaluate_on(node: link, expression: "this.click()", wait: 0.1)` | waits for the new page | `NoMethodError` | `page.wait_for_navigation!(0.1) { link.evaluate("this.click()") }` |

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
