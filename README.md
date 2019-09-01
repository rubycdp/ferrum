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

#### back

Navigate to the previous page in history.

#### forward

Navigate to the next page in history.

#### refresh

Reload current page.

#### status : `Integer`

Contains the status code of the response (e.g., 200 for a success).


## Finders

#### at_css(selector, \*\*options) : `Node` | `nil`

Find node by selector. Runs `document.querySelector` within the document or
provided node.

  * selector `String`
  * options `Hash`
    * :within `Node` | `nil`

#### css(selector, \*\*options) : `Array<Node>` | `[]`

Find nodes by selector. The method runs `document.querySelectorAll` within the
document or provided node.

* selector `String`
* options `Hash`
  * :within `Node` | `nil`

#### at_xpath(selector, \*\*options) : `Node` | `nil`

Find node by xpath.

* selector `String`
* options `Hash`
  * :within `Node` | `nil`

#### xpath(selector, \*\*options) : `Array<Node>` | `[]`

Find nodes by xpath.

* selector `String`
* options `Hash`
  * :within `Node` | `nil`

#### current_url : `String`

Returns current window location href.

#### title : `String`

Returns current window title

#### body : `String`

Returns current page's html.


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

#### cookies : `Hash<String, Cookie>`

Returns cookies hash

#### set_cookie(\*\*options)

Sets given values as cookie

* options `Hash`
  * :name `String`
  * :value `String`
  * :domain `String`
  * :expires `Integer`

#### remove_cookie(\*\*options)

Removes given cookie

* options `Hash`
  * :name `String`
  * :domain `String`
  * :url `String`

#### clear_cookies

Removes all cookies

## Headers

#### headers=
#### add_headers
#### add_header


## JavaScript

#### evaluate
#### evaluate_on
#### evaluate_async
#### execute


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
