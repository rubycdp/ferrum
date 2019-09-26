# Ferrum - fearless Ruby Chrome driver

[![Build Status](https://travis-ci.org/route/ferrum.svg?branch=master)](https://travis-ci.org/route/ferrum)

<img align="right" width="95" height="95"
     alt="Ferrum logo"
     src="https://raw.githubusercontent.com/route/ferrum/master/logo.svg?sanitize=true">

As simple as Puppeteer, though even simpler.

It is Ruby clean and high-level API to Chrome. Runs headless by default,
but you can configure it to run in a non-headless mode. All you need is Ruby and
Chrome/Chromium. Ferrum connects to the browser via DevTools Protocol.

Relation to [Cuprite](https://github.com/machinio/cuprite). Cuprite used to have
this code inside in one form or another but the thing is you don't need capybara
if you are going to crawl sites. You crawl, not test. Besides that clean
lightweight API to browser is what Ruby was missing, so here it comes.

## Install

There's no official Chrome or Chromium package for Linux don't install it this
way because it either will be outdated or unofficial, both are bad. Download it
from official [source](https://www.chromium.org/getting-involved/download-chromium).
Chrome binary should be in the `PATH` or `BROWSER_PATH` or you can pass it as an
option to browser instance `:browser_path`.

Add this to your Gemfile:

``` ruby
gem "ferrum"
```

Navigate to a website and save a screenshot:

```ruby
browser = Ferrum::Browser.new
browser.goto("https://google.com")
browser.screenshot(path: "google.png")
browser.quit
```

Interact with a page:

```ruby
browser = Ferrum::Browser.new
browser.goto("https://google.com")
input = browser.at_xpath("//div[@id='searchform']/form//input[@type='text']")
input.focus.type("Ruby headless driver for Capybara", :Enter)
browser.at_css("a > h3").text # => "machinio/cuprite: Headless Chrome driver for Capybara - GitHub"
browser.quit
```

Evaluate some JavaScript and get full width/height:

```ruby
browser = Ferrum::Browser.new
browser.goto("https://www.google.com/search?q=Ruby+headless+driver+for+Capybara")
width, height = browser.evaluate <<~JS
  [document.documentElement.offsetWidth,
   document.documentElement.offsetHeight]
JS
# => [1024, 1931]
browser.quit
```

Do any mouse movements you like:

```ruby
# Trace a 100x100 square
browser = Ferrum::Browser.new
browser.goto("https://google.com")
browser.mouse
  .move(x: 0, y: 0)
  .down
  .move(x: 0, y: 100)
  .move(x: 100, y: 100)
  .move(x: 100, y: 0)
  .move(x: 0, y: 0)
  .up

browser.quit
```

## Customization ##

You can customize options with the following code in your test setup:

``` ruby
Ferrum::Browser.new(options)
```

* options `Hash`
  * `:browser_path` (String) - Path to chrome binary, you can also set ENV
      variable as `BROWSER_PATH=some/path/chrome bundle exec rspec`.
  * `:headless` (Boolean) - Set browser as headless or not, `true` by default.
  * `:slowmo` (Integer | Float) - Set a delay to wait before sending command.
      Usefull companion of headless option, so that you have time to see changes.
  * `:logger` (Object responding to `puts`) - When present, debug output is
      written to this object.
  * `:timeout` (Numeric) - The number of seconds we'll wait for a response when
      communicating with browser. Default is 5.
  * `:js_errors` (Boolean) - When true, JavaScript errors get re-raised in Ruby.
  * `:window_size` (Array) - The dimensions of the browser window in which to
      test, expressed as a 2-element array, e.g. [1024, 768]. Default: [1024, 768]
  * `:browser_options` (Hash) - Additional command line options,
      [see them all](https://peter.sh/experiments/chromium-command-line-switches/)
      e.g. `{ "ignore-certificate-errors" => nil }`
  * `:extensions` (Array) - An array of JS files to be preloaded into the browser
  * `:port` (Integer) - Remote debugging port for headless Chrome
  * `:host` (String) - Remote debugging address for headless Chrome
  * `:url` (String) - URL for a running instance of Chrome. If this is set, a
      browser process will not be spawned.
  * `:process_timeout` (Integer) - How long to wait for the Chrome process to
      respond on startup


#### The API below is for master branch and a subject to change before 1.0


## Navigation

#### goto(url) : `String`

Navigate page to.

  * url `String` The url should include scheme unless you set `base_url` when
  configuring driver.

```ruby
browser.goto("https://github.com/")
```

#### back

Navigate to the previous page in history.

```ruby
browser.goto("https://github.com/")
browser.at_xpath("//a").click
browser.back
```

#### forward

Navigate to the next page in history.

```ruby
browser.goto("https://github.com/")
browser.at_xpath("//a").click
browser.back
browser.forward
```

#### refresh

Reload current page.

```ruby
browser.goto("https://github.com/")
browser.refresh
```


## Finders

#### at_css(selector, \*\*options) : `Node` | `nil`

Find node by selector. Runs `document.querySelector` within the document or
provided node.

  * selector `String`
  * options `Hash`
    * :within `Node` | `nil`

```ruby
browser.goto("https://github.com/")
browser.at_css("a[aria-label='Issues you created']") # => Node
```


#### css(selector, \*\*options) : `Array<Node>` | `[]`

Find nodes by selector. The method runs `document.querySelectorAll` within the
document or provided node.

* selector `String`
* options `Hash`
  * :within `Node` | `nil`

```ruby
browser.goto("https://github.com/")
browser.css("a[aria-label='Issues you created']") # => [Node]
```

#### at_xpath(selector, \*\*options) : `Node` | `nil`

Find node by xpath.

* selector `String`
* options `Hash`
  * :within `Node` | `nil`

```ruby
browser.goto("https://github.com/")
browser.at_xpath("//a[@aria-label='Issues you created']") # => Node
```

#### xpath(selector, \*\*options) : `Array<Node>` | `[]`

Find nodes by xpath.

* selector `String`
* options `Hash`
  * :within `Node` | `nil`

```ruby
browser.goto("https://github.com/")
browser.xpath("//a[@aria-label='Issues you created']") # => [Node]
```

#### current_url : `String`

Returns current window location href.

```ruby
browser.goto("https://google.com/")
browser.current_url # => "https://www.google.com/"
```

#### title : `String`

Returns current window title

```ruby
browser.goto("https://google.com/")
browser.title # => "Google"
```

#### body : `String`

Returns current page's html.

```ruby
browser.goto("https://google.com/")
browser.body # => '<html itemscope="" itemtype="http://schema.org/WebPage" lang="ru"><head>...
```


## Screenshots

#### screenshot(\*\*options) : `String` | `Integer`

Saves screenshot on a disk or returns it as base64.

* options `Hash`
  * :path `String` to save a screenshot on the disk. `:encoding` will be set to
    `:binary` automatically
  * :encoding `Symbol` `:base64` | `:binary` you can set it to return image as
    Base64
  * :format `String` "jpeg" | "png"
  * :quality `Integer` 0-100 works for jpeg only
  * :full `Boolean` whether you need full page screenshot or a viewport
  * :selector `String` css selector for given element
  * :scale `Float` zoom in/out

```ruby
browser.goto("https://google.com/")
# Save on the disk in PNG
browser.screenshot(path: "google.png") # => 134660
# Save on the disk in JPG
browser.screenshot(path: "google.jpg") # => 30902
# Save to Base64 the whole page not only viewport and reduce quality
browser.screenshot(full: true, quality: 60) # "iVBORw0KGgoAAAANSUhEUgAABAAAAAMACAYAAAC6uhUNAAAAAXNSR0IArs4c6Q...
```

#### pdf(\*\*options) : `String` | `Integer`

Saves PDF on a disk or returns it as base64.

* options `Hash`
  * :path `String` to save a pdf on the disk. `:encoding` will be set to
    `:binary` automatically
  * :encoding `Symbol` `:base64` | `:binary` you can set it to return pdf as
    Base64
  * :landscape `Boolean` paper orientation. Defaults to false.
  * :scale `Float` zoom in/out
  * :paper_width `Float` set paper width
  * :paper_height `Float` set paper height
  * See other [native options](https://chromedevtools.github.io/devtools-protocol/tot/Page#method-printToPDF) you can pass

```ruby
browser.goto("https://google.com/")
# Save to disk as a PDF
browser.pdf(path: "google.pdf", paper_width: 1.0, paper_height: 1.0) # => 14983
```


## Network

browser.network

#### traffic `Array<Network::Exchange>`

Returns all information about network traffic as `Network::Exchange` instance
which in general is a wrapper around `request`, `response` and `error`.

```ruby
browser.goto("https://github.com/")
browser.network.traffic # => [#<Ferrum::Network::Exchange, ...]
```

#### request : `Network::Request`

Page request of the main frame.

```ruby
browser.goto("https://github.com/")
browser.network.request # => #<Ferrum::Network::Request...
```

#### response : `Network::Response`

Page response of the main frame.

```ruby
browser.goto("https://github.com/")
browser.network.response # => #<Ferrum::Network::Response...
```

#### status : `Integer`

Contains the status code of the main page response (e.g., 200 for a
success). This is just a shortcut for `response.status`.

```ruby
browser.goto("https://github.com/")
browser.network.status # => 200
```

#### clear(type)

Clear browser's cache or collected traffic.

* type `Symbol` it is either `:traffic` or `:cache`

```ruby
traffic = browser.network.traffic # => []
browser.goto("https://github.com/")
traffic.size # => 51
browser.network.clear(:traffic)
traffic.size # => 0
```

#### intercept(\*\*options)

Set request interception for given options. This method is only sets request
interception, you should use `on` callback to catch requests and abort or
continue them.

* options `Hash`
  * :pattern `String` \* by default
  * :resource_type `Symbol` one of the [resource types](https://chromedevtools.github.io/devtools-protocol/tot/Network#type-ResourceType)

```ruby
browser = Ferrum::Browser.new
browser.network.intercept
browser.on(:request) do |request|
  if request.match?(/bla-bla/)
    request.abort
  else
    request.continue
  end
end
browser.goto("https://google.com")
```

#### authorize(\*\*options)

If site uses authorization you can provide credentials using this method.

* options `Hash`
  * :type `Symbol` `:server` | `:proxy` site or proxy authorization
  * :user `String`
  * :password `String`

```ruby
browser.network.authorize(user: "login", password: "pass")
browser.goto("http://example.com/authenticated")
puts browser.network.status # => 200
puts browser.body # => Welcome, authenticated client
```


### Mouse

browser.mouse

#### scroll_to(x, y)

Scroll page to a given x, y

  * x `Integer` the pixel along the horizontal axis of the document that you
  want displayed in the upper left
  * y `Integer` the pixel along the vertical axis of the document that you want
  displayed in the upper left

```ruby
browser.goto("https://www.google.com/search?q=Ruby+headless+driver+for+Capybara")
browser.mouse.scroll_to(0, 400)
```

#### click(\*\*options) : `Mouse`

Click given coordinates, fires mouse move, down and up events.

* options `Hash`
  * :x `Integer`
  * :y `Integer`
  * :delay `Float` defaults to 0. Delay between mouse down and mouse up events
  * :button `Symbol` :left | :right, defaults to :left
  * :count `Integer` defaults to 1
  * :modifiers `Integer` bitfield for key modifiers. See`keyboard.modifiers`

#### down(\*\*options) : `Mouse`

Mouse down for given coordinates.

* options `Hash`
  * :button `Symbol` :left | :right, defaults to :left
  * :count `Integer` defaults to 1
  * :modifiers `Integer` bitfield for key modifiers. See`keyboard.modifiers`

#### up(\*\*options) : `Mouse`

Mouse up for given coordinates.

* options `Hash`
  * :button `Symbol` :left | :right, defaults to :left
  * :count `Integer` defaults to 1
  * :modifiers `Integer` bitfield for key modifiers. See`keyboard.modifiers`

#### move(x:, y:, steps: 1) : `Mouse`

Mouse move to given x and y.

* options `Hash`
  * :x `Integer`
  * :y `Integer`
  * :steps `Integer` defaults to 1. Sends intermediate mousemove events.

### Keyboard

browser.keyboard

#### down(key) : `Keyboard`

Dispatches a keydown event.

* key `String` | `Symbol` Name of key such as "a", :enter, :backspace

#### up(key) : `Keyboard`

Dispatches a keyup event.

* key `String` | `Symbol` Name of key such as "b", :enter, :backspace

#### type(\*keys) : `Keyboard`

Sends a keydown, keypress/input, and keyup event for each character in the text.

* text `String` | `Array<String> | Array<Symbol>` A text to type into a focused
  element, `[:Shift, "s"], "tring"`

#### modifiers(keys) : `Integer`

Returns bitfield for a given keys

* keys `Array<Symbol>` :alt | :ctrl | :command | :shift


## Cookies

browser.cookies

#### all : `Hash<String, Cookie>`

Returns cookies hash


```ruby
browser.cookies.all # => {"NID"=>#<Ferrum::Cookies::Cookie:0x0000558624b37a40 @attributes={"name"=>"NID", "value"=>"...", "domain"=>".google.com", "path"=>"/", "expires"=>1583211046.575681, "size"=>178, "httpOnly"=>true, "secure"=>false, "session"=>false}>}
```

#### [](value) : `Cookie`

Returns cookie

* value `String`

```ruby
browser.cookies["NID"] # => <Ferrum::Cookies::Cookie:0x0000558624b67a88 @attributes={"name"=>"NID", "value"=>"...", "domain"=>".google.com", "path"=>"/", "expires"=>1583211046.575681, "size"=>178, "httpOnly"=>true, "secure"=>false, "session"=>false}>
```

#### set(\*\*options) : `Boolean`

Sets given values as cookie

* options `Hash`
  * :name `String`
  * :value `String`
  * :domain `String`
  * :expires `Integer`

```ruby
browser.cookies.set(name: "stealth", value: "omg", domain: "google.com") # => true
```

#### remove(\*\*options) : `Boolean`

Removes given cookie

* options `Hash`
  * :name `String`
  * :domain `String`
  * :url `String`

```ruby
browser.cookies.remove(name: "stealth", domain: "google.com") # => true
```

#### clear : `Boolean`

Removes all cookies for current page

```ruby
browser.cookies.clear # => true
```

## Headers

browser.headers

#### get : `Hash`

Get all headers

#### set(headers) : `Boolean`

Set given headers. Eventually clear all headers and set given ones.

* headers `Hash` key-value pairs for example `"User-Agent" => "Browser"`

#### add(headers) : `Boolean`

Adds given headers to already set ones.

* headers `Hash` key-value pairs for example `"Referer" => "http://example.com"`

#### clear : `Boolean`

Clear all headers.


## JavaScript

#### evaluate(expression, \*args)

Evaluate and return result for given JS expression

* expression `String` should be valid JavaScript
* args `Object` you can pass arguments, though it should be a valid `Node` or a
simple value.

```ruby
browser.evaluate("[window.scrollX, window.scrollY]")
```

#### evaluate_async(expression, wait_time, \*args)

Evaluate asynchronous expression and return result

* expression `String` should be valid JavaScript
* wait_time How long we should wait for Promise to resolve or reject
* args `Object` you can pass arguments, though it should be a valid `Node` or a
simple value.

```ruby
browser.evaluate_async(%(arguments[0]({foo: "bar"})), 5) # => { "foo" => "bar" }
```

#### execute(expression, \*args)

Execute expression. Doesn't return the result

* expression `String` should be valid JavaScript
* args `Object` you can pass arguments, though it should be a valid `Node` or a
simple value.

```ruby
browser.execute(%(1 + 1)) # => true
```


## Frames

#### frame_url
#### frame_title
#### within_frame(frame, &block)

Play around inside given frame

```ruby
browser.goto("https://developer.mozilla.org/en-US/docs/Web/HTML/Element/iframe")
frame = browser.at_xpath("//iframe")
browser.within_frame(frame) do
  puts browser.frame_title # => HTML Demo: <iframe>
  puts browser.frame_url # => https://interactive-examples.mdn.mozilla.net/pages/tabbed/iframe.html
end
```


## Dialog

#### accept(text)

Accept dialog with given text or default prompt if applicable

  * text `String`

#### dismiss

Dismiss dialog

```ruby
browser = Ferrum::Browser.new
browser.on(:dialog) do |dialog|
  if dialog.match?(/bla-bla/)
    dialog.accept
  else
    dialog.dismiss
  end
end
browser.goto("https://google.com")
```


## Thread safety ##

Ferrum is fully thread-safe. You can create one browser or a few as you wish and
start playing around using threads. Example below shows how to create a few pages
which share the same context. Context is similar to an incognito profile but you
can have more than one, think of it like it's independent browser session:

```ruby
browser = Ferrum::Browser.new
context = browser.contexts.create

t1 = Thread.new(context) do |c|
  page = c.create_page
  page.goto("https://www.google.com/search?q=Ruby+headless+driver+for+Capybara")
  page.screenshot(path: "t1.png")
end

t2 = Thread.new(context) do |c|
  page = c.create_page
  page.goto("https://www.google.com/search?q=Ruby+static+typing")
  page.screenshot(path: "t2.png")
end

t1.join
t2.join

context.dispose
browser.quit
```

or you can create two independent contexts:

```ruby
browser = Ferrum::Browser.new

t1 = Thread.new(browser) do |b|
  context = b.contexts.create
  page = context.create_page
  page.goto("https://www.google.com/search?q=Ruby+headless+driver+for+Capybara")
  page.screenshot(path: "t1.png")
  context.dispose
end

t2 = Thread.new(browser) do |b|
  context = b.contexts.create
  page = context.create_page
  page.goto("https://www.google.com/search?q=Ruby+static+typing")
  page.screenshot(path: "t2.png")
  context.dispose
end

t1.join
t2.join

browser.quit
```
