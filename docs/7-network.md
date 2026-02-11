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

#### wait_for_idle(\*\*options) : `Boolean`

Waits for network idle, returns `true` in case of success and `false` if there are still connections.

* options `Hash`
    * :connections `Integer` how many connections are allowed for network to be
      idling, `0` by default
    * :duration `Float` sleep for given amount of time and check again, `0.05` by
      default
    * :timeout `Float` during what time we try to check idle, `browser.timeout`
      by default

```ruby
page.go_to("https://example.com/")
page.at_xpath("//a[text() = 'No UI changes button']").click
page.network.wait_for_idle # => true
```

#### wait_for_idle!(\*\*options)

Waits for network idle or raises `Ferrum::TimeoutError` error. Accepts same arguments as `wait_for_idle`.

```ruby
page.go_to("https://example.com/")
page.at_xpath("//a[text() = 'No UI changes button']").click
page.network.wait_for_idle! # might raise an error
```

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

#### intercept(\*\*options)

Set request interception for given options. This method is only sets request
interception, you should use `on` callback to catch requests and abort or
continue them.

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
puts page.body # => Welcome, authenticated client
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

#### emulate_network_conditions(\*\*options)

Activates emulation of network conditions.

* options `Hash`
    * :offline `Boolean` emulate internet disconnection, `false` by default
    * :latency `Integer` minimum latency from request sent to response headers received (ms), `0` by
      default
    * :download_throughput `Integer` maximal aggregated download throughput (bytes/sec), `-1`
      by default, disables download throttling
    * :upload_throughput `Integer` maximal aggregated upload throughput (bytes/sec), `-1`
      by default, disables download throttling
    * :connection_type `String` connection type if known, one of: none, cellular2g, cellular3g, cellular4g,
      bluetooth, ethernet, wifi, wimax, other. `nil` by default

```ruby
page.network.emulate_network_conditions(connection_type: "cellular2g")
page.go_to("https://github.com/")
```

#### offline_mode

Activates offline mode for a page.

```ruby
page.network.offline_mode
page.go_to("https://github.com/") # => Ferrum::StatusError (Request to https://github.com/ failed(net::ERR_INTERNET_DISCONNECTED))
```

#### cache(disable: `Boolean`)

Toggles ignoring cache for each request. If true, cache will not be used.

```ruby
page.network.cache(disable: true)
```
