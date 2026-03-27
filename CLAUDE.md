# Ferrum - Claude Code Instructions

## What is this project?

Ferrum is a Ruby gem that drives headless Chrome/Chromium through the Chrome DevTools Protocol (CDP). It connects via WebSocket, sends JSON-RPC commands, and provides a Ruby object model for browser automation. No Selenium, no chromedriver -- just a direct WebSocket to Chrome.

## Quick start

```bash
bundle install
bundle exec rake        # runs full test suite (needs Chrome installed)
HEADLESS=false bundle exec rake  # watch tests run in a visible browser
```

## Architecture you need to know

The delegation chain is the key to understanding this codebase:

```
Browser -> Contexts -> Context -> Target -> Page -> Frame
                                              |
                                              +-> Mouse, Keyboard, Network, Headers, Cookies, Downloads, Tracing
```

All Chrome communication flows through a single path:

```
Ruby code -> Page#command -> SessionClient#command -> Client#send_message -> WebSocket#send_message -> Chrome
Chrome -> WebSocket reader thread -> Client message loop -> Subscriber (priority/regular queues) -> event callbacks
```

**Flatten mode** (default, `flatten: true`): One WebSocket for the browser + all pages. `SessionClient` tags each message with `sessionId` to route it to the correct target. This is the only mode you should care about for most work.

## Key conventions

### CDP command pattern

Every interaction with Chrome is a CDP method call:

```ruby
command("Page.navigate", url: "https://example.com")
command("DOM.getDocument", depth: 0)
command("Runtime.callFunctionOn", functionDeclaration: "...", executionContextId: id)
```

Page#command adds `wait` and `slowmoable` on top of the raw client command. The `wait` parameter triggers navigation-aware waiting (resets an event, waits for frame stop loading).

### JS evaluation

All DOM queries and JS execution go through `Frame::Runtime#call`, which uses `Runtime.callFunctionOn`. The return value deserialization in `handle_response` converts CDP remote objects back to Ruby primitives, arrays, hashes, or `Node` instances. This is one of the most complex parts of the codebase.

### Concurrency model

Ferrum uses `concurrent-ruby` extensively:
- `Concurrent::Map` for frames, targets, contexts (thread-safe hash)
- `Concurrent::IVar` for pending CDP command responses (one-shot future)
- `Concurrent::MVar` for frame execution context IDs (blocking take/put)
- `Concurrent::Hash` and `Concurrent::Array` for subscriber storage

Three background threads run per browser: WebSocket reader, regular event subscriber, priority event subscriber.

### Error handling

CDP errors in `Client#raise_browser_error` are mapped to specific Ruby exceptions:
- "No node with given id found" -> `NodeNotFoundError`
- "Cannot find context with specified id" -> `NoExecutionContextError`
- Timeout waiting for CDP response -> `TimeoutError`
- Browser process dies -> `DeadBrowserError`

`Frame::Runtime` retries on `NodeNotFoundError` and `NoExecutionContextError` because these are often transient during page loads.

## How to write tests

Tests are integration tests that run against a real Chrome browser and a local Sinatra app.

```ruby
# spec/your_feature_spec.rb
describe Ferrum::YourFeature do
  # `browser` and `page` are available via "Global helpers" shared context
  # `server` gives you the test Sinatra app

  it "does something" do
    page.go_to("/some_view")           # navigates to spec/support/views/some_view.erb
    node = page.at_css("#my-element")  # find element
    node.click                         # interact
    expect(page.body).to include("expected text")
  end
end
```

- Add test HTML views to `spec/support/views/` as ERB files
- Add test routes to `spec/support/application.rb` (Sinatra app)
- Use `page` (creates a new page each test group), not `browser.page` directly
- Call `reset` in after hooks (already done by spec_helper)
- On CI, screenshots and logs are saved to `/tmp/ferrum/` on failure

## File organization rules

- All source files use `# frozen_string_literal: true`
- One class per file, file path mirrors class name: `Ferrum::Network::Exchange` -> `lib/ferrum/network/exchange.rb`
- Specs mirror lib: `lib/ferrum/network.rb` -> `spec/network_spec.rb`
- Unit specs go in `spec/unit/`
- Page capabilities are split into modules under `lib/ferrum/page/` (Screenshot, Frames, Animation, etc.) and included into Page
- Frame capabilities are split into `lib/ferrum/frame/dom.rb` and `lib/ferrum/frame/runtime.rb`

## Common pitfalls

1. **Don't forget `wait` in page commands.** Navigation commands need `wait: GOTO_WAIT` or `wait: timeout` so Ferrum waits for the page to finish loading.

2. **Execution context can disappear.** When a page navigates, its execution context changes. The `Concurrent::MVar` in Frame handles this, but code that caches `execution_id` across navigations will break.

3. **Node IDs are ephemeral.** Chrome can reassign node IDs. That's why `Node#==` compares `backendNodeId` from the description, not `node_id`.

4. **Network interception has ordering constraints.** `intercept` must be called before `on(:request)`. The `Subscriber` priority queue ensures Fetch events are handled promptly.

5. **Thread safety matters.** Anything touched by the WebSocket reader thread and the main thread must use concurrent-ruby data structures.

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `FERRUM_DEFAULT_TIMEOUT` | 5 | CDP command timeout (seconds) |
| `FERRUM_PROCESS_TIMEOUT` | 10 | Browser startup timeout (seconds) |
| `FERRUM_DEBUG` | unset | Enable debug logging to stdout |
| `BROWSER_PATH` | auto-detected | Path to Chrome binary |
| `HEADLESS` | true | Set to "false" for visible browser |
| `SLOWMO` | 0 | Delay between commands (seconds) |

## Type signatures

RBS type signatures are in `sig/`. If you change a public method signature, update the corresponding `.rbs` file.

## What NOT to do

- Do not add Selenium or chromedriver dependencies. Ferrum's value is direct CDP communication.
- Do not introduce global mutable state. Use the existing concurrent-ruby patterns.
- Do not break the delegation chain (Browser -> Page -> Frame). Users depend on calling methods like `browser.at_css` directly.
- Do not add heavy runtime dependencies. The gem has only 5 runtime deps and should stay lean.
- Do not use `sleep` for synchronization in production code. Use the Event/IVar/MVar patterns already established.
