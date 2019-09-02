# Ferrum - fearless Ruby Chrome driver

As simple as Puppeteer, though even simpler.

It is Ruby clean and high-level API to Chrome. Runs headless by default,
but you can configure it to run in a non-headless mode. All you need is Ruby and
Chrome/Chromium. Ferrum connects to the browser via DevTools Protocol.

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

#### The API below is correct but a subject to change before `1.0`

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

#### status : `Integer`

Contains the status code of the response (e.g., 200 for a success).

```ruby
browser.goto("https://github.com/")
browser.status # => 200
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
  * :path `String` to save a screenshot on the disk. If passed `:encoding` is
    set to `:binary` automatically
  * :encoding `Symbol` `:base64` | `:binary` you can set it to return image as
    Base64
  * :format `String` "jpeg" | "png" | "pdf"
  * :quality `Integer` 0-100 works for jpeg only
  * :full `Boolean` whether you need full page screenshot or a viewport
  * :selector `String` css selector for given element

```ruby
browser.goto("https://google.com/")
# Save on the disk in PNG
browser.screenshot(path: "google.png") # => 134660
# Save on the disk in JPG
browser.screenshot(path: "google.jpg") # => 30902
# Save to Base64 the whole page not only viewport and reduce quality
browser.screenshot(full: true, quality: 60) # "iVBORw0KGgoAAAANSUhEUgAABAAAAAMACAYAAAC6uhUNAAAAAXNSR0IArs4c6Q...
```


#### zoom_factor = value

Zoom in, zoom out

* value `Float`

#### paper_size = value

Set paper size. Works for PDF only.

* value `Hash`
  * :width `Float`
  * :height `Float`


## Network

#### network_traffic : `Array<Network::Request>`

Returns all information about network traffic as a request/response array.

#### clear_network_traffic

Cleans up collected data.

#### response_headers : `Hash`

Returns all headers for a given request in `goto` method.


## Input

#### scroll_to(x, y)

Scroll page to a given x, y

  * x `Integer` the pixel along the horizontal axis of the document that you
  want displayed in the upper left
  * y `Integer` the pixel along the vertical axis of the document that you want
  displayed in the upper left

### Mouse

browser.mouse

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
#### switch_to_frame


## Modals

#### find_modal
#### accept_confirm
#### dismiss_confirm
#### accept_prompt
#### dismiss_prompt
#### reset_modals


## Auth

#### authorize
#### proxy_authorize


## Interception

#### url_whitelist=
#### url_blacklist=
