# AGENTS.md

Ferrum is a pure-Ruby driver for Chrome over the Chrome DevTools Protocol (CDP). No Selenium, no WebDriver,
no Node. Chrome/Chromium only: Firefox support was removed, don't add it back or plan for BiDi.

## Layout

- `lib/ferrum/` - the library. `Browser` owns a `Client` (WebSocket + `Client::Subscriber` event dispatch) and
  `Contexts`, which tracks `Context`s and their `Target`s; a target connects as a `Page` or `Worker`.
- `sig/` - RBS signatures mirroring `lib/`. Keep them in sync with every public or private method you add or change.
- `spec/` - RSpec suite, see [Tests](#tests).
- `docs/` - user-facing guides, numbered by chapter.
- `CHANGELOG.md` - `## [Unreleased]` section on top, grouped into Added / Changed / Fixed / Removed.

## Commands

```sh
bundle exec rake                      # whole suite (rspec with -w), what CI runs
bundle exec rspec spec/page_spec.rb   # one file
bundle exec rubocop                   # lint, must be clean
HEADLESS=false bundle exec rspec ...  # watch the browser
```

The suite boots a real Chrome and a Sinatra/Puma test app (`spec/support/application.rb`, views in
`spec/support/views/`). CI runs Ruby 3.2 to 4.0 against stable Chrome.

## Tests

- **Prefer system/feature specs**: drive a real browser against the test app and assert on observable behavior.
  They live in `spec/` next to the feature, e.g. `spec/page_spec.rb`, `spec/network/`.
- **Unit specs go in `spec/unit/` and nowhere else.** A unit spec tests one class in isolation or its internals:
  it builds objects with `allocate` or `instance_variable_set`, or asserts on internal calls and state. A spec that
  drives the browser and asserts observable behavior stays a feature spec even if it stubs one call, e.g. to
  simulate a Chrome failure. Mirror the `lib/` path:
  `lib/ferrum/contexts.rb` -> `spec/unit/contexts_spec.rb`, `lib/ferrum/client/web_socket.rb` ->
  `spec/unit/client/web_socket_spec.rb`. Never add them to the feature spec files in `spec/`.
- Don't test private methods; cover them through the public API.
- Structure every spec file in one of two shapes, nothing else:

  ```ruby
  describe Ferrum::Context do
    describe "#windows" do
      it "waits for the window to load" do
  ```

  ```ruby
  describe Ferrum::Cookies do
    describe "#each" do
      context "when a block is given" do
        it "yields each cookie" do
  ```

  The top `describe` is the class, and the file path mirrors that class's path in `lib/`, for feature and unit
  specs alike: `Ferrum::Page::Screenshot` -> `spec/page/screenshot_spec.rb`, `Ferrum::Browser::Process` ->
  `spec/unit/browser/process_spec.rb`. Each nested `describe` names one public method (`"#method"`, `".method"` for
  class methods), never a topic like `"context scope"`.
- Use contexts only for contrasting groups, at least two that oppose each other (`"when a block is given"` /
  `"when no block is given"`). A single condition isn't a context: keep the examples flat and put the condition in
  the example name, e.g. `it "sets cookies for given domain when base_url isn't set"`. The exception is a context
  that carries `let`, hooks (`before`/`after`/`around`) or tags its examples share; it may sit next to plain
  examples. Never nest contexts.
- Every example must be runnable alone with `rspec spec/file_spec.rb:LINE`, so each one gets its own `it` on its
  own line. No `shared_examples`/`include_examples` and no loops that generate examples. Share the steps and
  assertions through a helper method in the `describe` instead, and call it from one-line examples, one per
  variant. The only exception is the data-table loops in `spec/unit/frame/script_spec.rb`.
- Start every example name with a verb in the third person: "yields each cookie", "returns the cookie with the
  given name". Never "must ...", "should ..." or a bare noun.
- Almost no comments in specs; the example name says what is checked.
- For a bug fix, make sure the new spec fails without the fix and passes with it.

## Code style

- Ruby >= 3.2, `# frozen_string_literal: true`, double quotes, RuboCop config in `.rubocop.yml`.
- Prefer self-documenting code over comments. Document public methods with YARD (`@param`, `@return`, `@raise`).
- Add or update RBS types in `sig/` for anything you touch.
- American English everywhere: code, comments, docs, errors, commits.

## Changelog

Add an entry under `## [Unreleased]` for user-visible changes. A few lines at most: what broke and what it does
now, with the issue/PR number in brackets, e.g. `[#641]`. No essays.

## Git

- Conventional commits: `<type>(<scope>): <subject>`, type one of `feat|fix|docs|style|ref|test|chore|perf`,
  imperative mood, no trailing period, subject <= 100 chars. Add a body for non-trivial changes.
- One logical change per commit.
- No AI attribution of any kind: no `Co-Authored-By`, no session links.
- Work on a branch, commit locally. Never push or open a PR unless asked.

## Chrome gotchas

- Don't add `--disable-crashpad-for-testing` to the default flags: it breaks a normally launched Chrome (child
  processes die with `FD ownership violation`, the network service crash-loops). Emulated amd64 Docker hides this.
- The browser's implicit (startup window) context can't be addressed by id or disposed, see `Context#implicit?`.
