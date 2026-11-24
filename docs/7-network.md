---
sidebar_position: 7
---

# Network

`page.network`

#### traffic `Array<Network::Exchange>`

Returns all information about network traffic as `Network::Exchange` instance
which in general is a wrapper around `request`, `response` and `error`.

```ruby
page.go_to("https://github.com/")
page.network.traffic # => [#<Ferrum::Network::Exchange, ...]
```

#### request : `Network::Request`

Page request of the main frame.

```ruby
page.go_to("https://github.com/")
page.network.request # => #<Ferrum::Network::Request...
```

#### response : `Network::Response`

Page response of the main frame.

```ruby
page.go_to("https://github.com/")
page.network.response # => #<Ferrum::Network::Response...
```

#### status : `Integer`

Contains the status code of the main page response (e.g., 200 for a
success). This is just a shortcut for `response.status`.

```ruby
page.go_to("https://github.com/")
page.network.status # => 200
```

#### wait_idle(\*\*options) : `true` | `nil`

Polls `idle?` until the network is idle, returns `true`, or `nil` if connections are still pending after `timeout`.
`wait_idle!` takes the same options and raises `Ferrum::TimeoutError` instead.

* options `Hash`
    * :connections `Integer` how many connections may still be pending, `0` by default
    * :timeout `Numeric` how long to keep trying, the page timeout by default
    * :interval `Numeric` seconds to sleep between attempts, `0.05` by default

```ruby
page.go_to("https://example.com/")
page.at_xpath("//a[text() = 'No UI changes button']").click
page.network.wait_idle # => true
page.network.wait_idle!(connections: 1)
```

#### idle?(connections: 0) : `Boolean`

Whether no more than `connections` requests are still pending.

#### clear(type)

Clear page's cache or collected traffic.

* type `Symbol` it is either `:traffic` or `:cache`

```ruby
traffic = page.network.traffic # => []
page.go_to("https://github.com/")
traffic.size # => 51
page.network.clear(:traffic)
traffic.size # => 0
```

#### on(name, &block) : `Integer`

Subscribes to a CDP event, or to one of the following pseudo-events. Returns a
subscription id you can pass to `off` to unsubscribe.

* `:request` an intercepted request, see `intercept` below. Requires `network.intercept` to be set up first.
  Callbacks run in the order they were added and the rest are skipped once one handles the request.
* `:response` a request's response once it's fully loaded, yielded as a `Network::Exchange`, see below. Works
  without `intercept`.
* `:auth` a proxy/basic auth challenge, see `authorize` below. Requires `network.intercept` to be set up first.
  Works like `:request`, an unhandled challenge gets Chrome's default response.
* `:dialog` a JS dialog (`alert`/`confirm`/`prompt`), see [Dialogs](./16-dialogs.md).
* anything else is passed straight through as a raw CDP event name, e.g. `page.on("Page.frameNavigated") { |params| ... }`.

##### on(:response, &block)

Subscribes to a callback fired once a request's response has fully loaded, i.e. after
Chrome's `Network.loadingFinished` event, so `exchange.response.body` is always
available. Doesn't require `intercept` to be set up. Despite the event's name, the block
receives the `Network::Exchange` for that request, not a `Network::Response`: it pairs
`exchange.request` with `exchange.response`, so you can tell which request a response
belongs to. It's never yielded for requests that fail to load (use `traffic` to inspect
those instead).

```ruby
page.on(:response) do |exchange|
  puts "#{exchange.response.status} #{exchange.url}"
end
page.go_to("https://github.com/")
```

#### off(name, id) : `void`

Unsubscribes a listener previously registered via `on`, given the subscription id `on` returned.

* name `Symbol | String` the same event name that was passed to `on`, e.g. `:request`, `:response`, `:auth`
* id `Integer` the subscription id returned by `on`

```ruby
id = page.on(:response) do |exchange|
  puts "#{exchange.response.status} #{exchange.url}"
end
page.go_to("https://github.com/")
page.off(:response, id)
```

#### intercept(\*\*options)

Set request interception for given options. This method is only sets request
interception, you should use `on` callback to catch requests and abort or
continue them.

`on(:request)` callbacks run in the order they were added and receive only the request. The first one that continues,
responds to or aborts it handles it and the rest are skipped, so a callback that doesn't care about a request just
returns. A request no callback handled is continued.

```ruby
page.on(:request) { |request| request.abort if request.match?(/ads/) }
page.on(:request) { |request| request.respond(body: "stub") if request.match?(/api/) }
```

`request.handled?` tells whether it was already handled.

* options `Hash`
    * :pattern `String` \* by default
    * :resource_type `Symbol` one of the [resource types](https://chromedevtools.github.io/devtools-protocol/tot/Network#type-ResourceType)

```ruby
browser = Ferrum::Browser.new
page = browser.create_page
page.network.intercept
page.on(:request) do |request|
  if request.match?(/bla-bla/)
    request.abort
  elsif request.match?(/lorem/)
    request.respond(body: "Lorem ipsum")
  else
    request.continue
  end
end
page.go_to("https://google.com")
```

#### authorize(\*\*options, &block)

If site or proxy uses authorization you can provide credentials using this method.

* options `Hash`
    * :type `Symbol` `:server` | `:proxy` site or proxy authorization
    * :user `String`
    * :password `String`
* &block accepts authenticated request, which you must subsequently allow or deny, if you don't
  care about unwanted requests just call `request.continue`.

```ruby
page.network.authorize(user: "login", password: "pass") { |req| req.continue }
page.go_to("http://example.com/authenticated")
puts page.network.status # => 200
puts page.html # => Welcome, authenticated client
```

Since Chrome implements authorize using request interception you must continue or abort authorized requests. If you
already have code that uses interception you can use `authorize` without block, but if not you are obliged to pass
block, so this is version doesn't pass block and can work just fine:

```ruby
browser = Ferrum::Browser.new
page = browser.create_page
page.network.intercept
page.on(:request) do |request|
  if request.resource_type == "Image"
    request.abort
  else
    request.continue
  end
end

page.network.authorize(user: "login", password: "pass", type: :proxy)

page.go_to("https://google.com")
```

You used to call `authorize` method without block, but since it's implemented using request interception there could be
a collision with another part of your code that also uses request interception, so that authorize allows the request
while your code denies but it's too late. The block is mandatory now.

#### throttle(\*\*options)

Slows the page's network down. Each call replaces the previous conditions and takes the page back online, Chrome keeps
a single set of them.

* options `Hash`
    * :latency `Integer` minimum latency from request sent to response headers received (ms), `0` by default
    * :download `Integer` maximal aggregated download throughput (bytes/sec), `-1` by default, no limit
    * :upload `Integer` maximal aggregated upload throughput (bytes/sec), `-1` by default, no limit
    * :connection_type `String` connection type if known, one of: none, cellular2g, cellular3g, cellular4g,
      bluetooth, ethernet, wifi, wimax, other. `nil` by default

```ruby
page.network.throttle(latency: 300, download: 50_000, connection_type: "cellular2g")
page.go_to("https://github.com/")
```

#### offline=(offline)

Takes the page offline or back online. It replaces the conditions set by `throttle`, so going back online leaves the
network unthrottled, call `throttle` again to restore them.

```ruby
page.network.offline = true
page.go_to("https://github.com/") # => Ferrum::StatusError (Request to https://github.com/ failed(net::ERR_INTERNET_DISCONNECTED))
page.network.offline = false
```

#### emulate(\*\*options)

Overrides the user agent, the accept language, the platform and the client hints the page reports, in the request
headers and in `navigator`. The options you don't pass keep their previous values, `nil` brings one back to the browser's default.
Setting `User-Agent` or `Accept-Language` with [headers](https://github.com/rubycdp/ferrum#headers) goes through
here too, the last one set wins. That is deprecated and stops in 0.22.

* options `Hash`
    * :user_agent `String` the `User-Agent` header and `navigator.userAgent`
    * :accept_language `String` the `Accept-Language` header and `navigator.language`
    * :platform `String` `navigator.platform`, e.g. `"Win32"`
    * :metadata `Hash` the client hints (`Sec-CH-UA-*` headers and `navigator.userAgentData`), needs all of
      `:platform`, `:platform_version`, `:architecture`, `:model` and `:mobile`. `:brands` and `:full_version_list` take
      an array of `{ brand:, version: }`, `:full_version`, `:bitness`, `:wow64` and `:form_factors` are optional

```ruby
page.network.emulate(platform: "Win32", accept_language: "de-DE")
page.go_to("https://github.com/")
```

While an override is active Chrome stops sending client hints, so a user agent that says Windows Chrome with no hints
stands out. Pass `:metadata` with it to keep them, the other options leave the hints off:

```ruby
page.network.emulate(
  user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/130.0.0.0 Safari/537.36",
  platform: "Win32",
  metadata: { platform: "Windows", platform_version: "15.0.0", architecture: "x86", model: "", mobile: false }
)
```

Once every option is back to `nil` the override is removed and Chrome sends its own client hints again.

#### cache=(enabled)

Turns the browser cache on or off for the page's requests.

```ruby
page.network.cache = false
```
