# Copilot Instructions for Ferrum

## Project overview

Ferrum is a Ruby gem for controlling headless Chrome via the Chrome DevTools Protocol (CDP). It connects over WebSocket, sends JSON-RPC commands, and provides a Ruby API for browser automation without Selenium or chromedriver.

## Architecture

The core delegation chain: `Browser -> Contexts -> Context -> Target -> Page -> Frame`

- **Browser** (`lib/ferrum/browser.rb`): Entry point. Spawns Chrome, creates the CDP Client, delegates page-level methods down the chain.
- **Client** (`lib/ferrum/client.rb`): WebSocket CDP client. Sends commands with incrementing IDs, receives responses via `Concurrent::IVar`. Routes events to Subscriber.
- **SessionClient** (`lib/ferrum/client.rb`): Per-target wrapper that adds `sessionId` to commands. Used in flatten mode (single WebSocket for all targets).
- **Page** (`lib/ferrum/page.rb`): Represents a browser tab. Composes Mouse, Keyboard, Network, Headers, Cookies, Downloads, Tracing. Handles navigation waiting logic.
- **Frame** (`lib/ferrum/frame.rb`): Document frame with DOM module (CSS/XPath finders) and Runtime module (JS evaluation via `Runtime.callFunctionOn`).
- **Node** (`lib/ferrum/node.rb`): DOM element. Click uses coordinate-based positioning with movement detection. Properties accessed via JS evaluation on the node's remote object.
- **Network** (`lib/ferrum/network.rb`): Monitors traffic as Exchange objects (request + response + error). Supports interception, authorization, blocklist/allowlist.

## Code conventions

- All files start with `# frozen_string_literal: true`
- One class per file, path mirrors namespace: `Ferrum::Network::Exchange` -> `lib/ferrum/network/exchange.rb`
- Heavy use of `Forwardable` for method delegation (Browser -> Page -> Frame)
- Page capabilities split into included modules: `Page::Screenshot`, `Page::Frames`, `Page::Animation`, etc.
- Frame capabilities split into `Frame::DOM` and `Frame::Runtime`
- Thread safety via `concurrent-ruby`: `Concurrent::Map`, `Concurrent::IVar`, `Concurrent::MVar`

## CDP command pattern

All Chrome interaction uses:
```ruby
command("Domain.method", param1: value1, param2: value2)
```

Page#command wraps Client#command with `wait` (navigation-aware waiting) and `slowmoable` (respects slowmo option) parameters.

## Testing conventions

- RSpec integration tests against a real Chrome browser
- Test app is a Sinatra application (`spec/support/application.rb`)
- Test server uses Puma (`spec/support/server.rb`)
- HTML fixtures in `spec/support/views/` as ERB files
- Shared context "Global helpers" provides `browser`, `page`, `network`, `traffic` accessors
- Specs mirror lib structure: `lib/ferrum/network.rb` -> `spec/network_spec.rb`
- Unit tests in `spec/unit/`
- Run tests: `bundle exec rake`
- CI tests Ruby 3.1 through 4.0

## When generating code

- Use CDP methods directly (e.g., `command("Page.enable")`) -- do not wrap in unnecessary abstraction layers
- Follow the existing pattern: compose objects in Page's constructor, subscribe to CDP events in `subscribe` methods
- New page capabilities should be modules under `lib/ferrum/page/` included into Page
- New network types go in `lib/ferrum/network/`
- Use `Concurrent::Map` instead of `Hash` for any data shared across threads
- Use `Utils::Attempt.with_retry` for operations that may fail transiently during page loads
- Map CDP errors to specific Ferrum error classes in `lib/ferrum/errors.rb`

## Important implementation details

- Node IDs are ephemeral -- Chrome reassigns them. `Node#==` compares `backendNodeId`.
- Execution context IDs change on navigation. `Frame#execution_id` uses `Concurrent::MVar` with blocking semantics.
- The Subscriber has two queues: priority (Fetch.requestPaused, Fetch.authRequired) and regular (everything else). This prevents network interception from being blocked.
- `Frame::Runtime#handle_response` deserializes CDP remote objects into Ruby types. It handles primitives, arrays, objects, dates, DOM nodes, null, and cyclic objects.

## Dependencies to be aware of

- `websocket-driver`: WebSocket protocol (not a full client -- Ferrum manages the TCP socket directly)
- `concurrent-ruby`: Thread-safe data structures used everywhere
- `addressable`: URI parsing
- Runtime deps are intentionally minimal (5 gems). Do not add heavy dependencies.
