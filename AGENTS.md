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
`spec/support/views/`). CI runs Ruby 3.1 to 4.0 against stable Chrome.

## Tests

- **Prefer system/feature specs**: drive a real browser against the test app and assert on observable behavior.
  They live in `spec/` next to the feature, e.g. `spec/page_spec.rb`, `spec/network/`.
- **Unit specs go in `spec/unit/` and nowhere else.** A spec is a unit spec if it stubs or mocks Ferrum's own
  objects (`allow(...).to receive`, `and_raise`, `and_wrap_original`), builds objects with `allocate` or
  `instance_variable_set`, or tests one class in isolation. Mirror the `lib/` path:
  `lib/ferrum/contexts.rb` -> `spec/unit/contexts_spec.rb`, `lib/ferrum/client/web_socket.rb` ->
  `spec/unit/client/web_socket_spec.rb`. Never add them to the feature spec files in `spec/`.
- Don't test private methods; cover them through the public API.
- Almost no comments in specs; the example name says what is checked.
- For a bug fix, make sure the new spec fails without the fix and passes with it.

## Code style

- Ruby >= 3.1, `# frozen_string_literal: true`, double quotes, RuboCop config in `.rubocop.yml`.
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
