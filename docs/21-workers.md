---
sidebar_position: 21
---

# Workers

Ferrum discovers dedicated workers (`new Worker`), shared workers (`new SharedWorker`) and service workers
(`navigator.serviceWorker.register`) spawned anywhere in a context.

Dedicated and shared workers are connected to automatically as soon as they're discovered, there's no need to wait
for them. Service workers are treated differently: attaching to a service worker's session prevents Chrome from ever
terminating it while the connection stays open, so Ferrum only discovers them and leaves the connection alone unless
you explicitly ask for it with `attach_target`.

#### workers : `Array<Worker>`

Returns all dedicated and shared workers spawned by pages in this context, already connected.

```ruby
page.execute <<~JS
  new Worker(URL.createObjectURL(new Blob(
    ["self.onmessage = () => self.postMessage(1 + 1)"],
    { type: "application/javascript" }
  )))
JS

sleep 0.1 # give Ferrum a moment to discover and connect to it

worker = browser.workers.first # => #<Ferrum::Worker @target_id="..." @url="blob:...">
worker.evaluate("1 + 1") # => 2
```

#### service_workers : `Array<Target>`

Returns service worker targets registered in this context. Unlike `workers`, these are plain `Target` objects and
are not connected to -- call `attach_target` first if you want to interact with one.

```ruby
page.evaluate_async(%(navigator.serviceWorker.register("/sw.js").then(arguments[0])), 5)

sleep 0.1

target = browser.service_workers.first # => #<Ferrum::Target @id="..." @type="service_worker">
target.connected? # => false
```

#### attach_target(target_id) : `Boolean`

Manually attaches to a target discovered via `service_workers`. Once attached, `target.worker` returns a connected
`Worker` for it, same as for a dedicated or shared worker.

```ruby
target = browser.service_workers.first
browser.attach_target(target.id)
target.worker.evaluate("1 + 1") # => 2
```

Keep in mind this keeps the service worker alive for as long as the connection is open -- only attach to the ones
you actually intend to talk to.

## Worker

A dedicated or shared Worker spawned by a page. Unlike `Page` it has no DOM, frames, mouse/keyboard, or navigation
history -- just a single global execution context and its own network activity, reachable through `worker.network`.

#### target_id : `String`

The worker's CDP target id.

#### url : `String`

The worker's script URL, e.g. a `blob:` URL for workers created from an inline `Blob`, as is common for
dedicated/shared workers.

#### network : `Network`

Same API as `page.network` -- see [Network](/docs/ferrum/network). Useful for asserting on requests a worker made on
its own, independently of the page that spawned it.

```ruby
worker.network.wait_for_idle
worker.network.traffic # => [#<Ferrum::Network::Exchange, ...]
```

#### evaluate / execute / evaluate_async

Same API as on `Page`/`Frame` -- see [JavaScript](/docs/ferrum/javascript). A worker has a single execution context,
so there's no frame to target.

```ruby
worker.evaluate("1 + 1") # => 2
```

#### on(:request) / on(:auth)

Subscribe to the worker's own network interception events, same as `page.on(:request)` -- see the `intercept` method
in [Network](/docs/ferrum/network).

#### close : `Boolean`

Closes the underlying CDP target and the worker's own connection.

```ruby
worker.close
```

## Example

Spawn a page's worker, wait for Ferrum to discover it, and read back a result it computes and posts to the page:

```ruby
page.go_to
page.execute <<~JS
  window.worker = new Worker(URL.createObjectURL(new Blob(
    ["self.onmessage = (e) => self.postMessage(e.data * 2)"],
    { type: "application/javascript" }
  )))
  window.worker.onmessage = (e) => { window.result = e.data }
JS

worker = nil
until worker
  worker = browser.workers.first
  sleep 0.05
end

page.execute("window.worker.postMessage(21)")
sleep 0.1
page.evaluate("window.result") # => 42
```
