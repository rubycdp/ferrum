---
sidebar_position: 2
---

# Customization

You can customize options with the following code in your test setup:

``` ruby
Ferrum::Browser.new(options)
```

* options `Hash`
    * `:headless` (Boolean) - Set browser as headless or not, `true` by default.
    * `:incognito` (Boolean) - Create an incognito profile for the browser startup window, `true` by default.
    * `:dockerize` (Boolean) - Provide CLI flags to the browser to run it in a container, `false` by default.
    * `:xvfb` (Boolean) - Run browser in a virtual framebuffer, `false` by default.
    * `:flatten` (Boolean) - Use one websocket connection to the browser and all the pages in flatten mode,
      `true` by default. When set to `false`, each page/target opens its own dedicated websocket connection instead
      of sharing the browser's connection.
    * `:window_size` (Array) - The dimensions of the browser window in which to
      test, expressed as a 2-element array, e.g. [1024, 768]. Default: [1024, 768]
    * `:extensions` (Array[String | Hash]) - An array of paths to files or JS
      source code to run in every page and iframe before it loads, e.g.:
      `["/path/to/script.js", { source: "window.secret = 'top'" }]`. Files are read in `Browser.new`.
    * `:logger` (Object responding to `puts`, or a `Logger`) - When present, debug output is
      written to it, see [Logging](#logging).
    * `:slowmo` (Integer | Float) - Set a delay in seconds to wait before sending command.
      Useful companion of headless option, so that you have time to see changes.
    * `:timeout` (Numeric) - The number of seconds we'll wait for a response when
      communicating with browser. Default is 5.
    * `:js_errors` (Boolean) - When true, JavaScript errors get re-raised in Ruby.
    * `:pending_connection_errors` (Boolean) - Raise `PendingConnectionsError` when main frame is still waiting
      for slow responses and timeout is reached. Default is false.
    * `:browser_name` (Symbol) - `:chrome` by default, `:opera` and `:edge` are
      also supported.
    * `:browser_path` (String) - Path to Chrome binary, you can also set ENV
      variable as `BROWSER_PATH=some/path/chrome bundle exec rspec`.
    * `:browser_options` (Hash) - Additional command line options,
      [see them all](https://peter.sh/experiments/chromium-command-line-switches/)
      e.g. `{ "ignore-certificate-errors" => nil }`
    * `:ignore_default_browser_options` (Boolean) - Ferrum has a number of default
      options it passes to the browser, if you set this to `true` then only
      options you put in `:browser_options` will be passed to the browser,
      except required ones of course.
    * `:port` (Integer) - Remote debugging port for headless Chrome.
    * `:host` (String) - Host we communicate with when spawning browser, `127.0.0.1` by default.
      Chrome always listens on `127.0.0.1` regardless of this option, so the host must resolve to `127.0.0.1` for
      Ferrum to actually be able to connect.
    * `:url` (String) - URL for a running instance of Chrome. If this is set, a
      browser process will not be spawned.
    * `:ws_url` (String) - Websocket url for a running instance of Chrome. If this is set, a
      browser process will not be spawned. It's higher priority than `:url`, setting both doesn't make sense.
    * `:process_timeout` (Integer) - How long to wait for the Chrome process to
      respond on startup.
    * `:ws_max_receive_size` (Integer) - How big messages to accept from Chrome
      over the web socket, in bytes. Defaults to 64MB. Incoming messages larger
      than this will cause a `Ferrum::DeadBrowserError`.
    * `:proxy` (Hash) - Specify proxy settings, [read more](https://github.com/rubycdp/ferrum#proxy)
    * `:save_path` (String) - Path to save attachments with [Content-Disposition](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Disposition) header.
    * `:env` (Hash) - Environment variables you'd like to pass through to the process

## Logging

With `:logger`, or `FERRUM_LOG` set to print to `$stdout`, Ferrum writes two channels:

* `protocol` - every CDP message sent (`▶`) and received (`◀`). String values longer than 1024 characters, such as
  Base64 screenshots, are cut; set `FERRUM_LOG_VALUE_LENGTH` to another length, or to `0` to keep them whole.
* `browser` - what the Chrome process Ferrum launched writes to stdout and stderr.

`FERRUM_LOG` picks what's written, as a comma-separated list:

```sh
FERRUM_LOG=*                         # everything, what to attach to a bug report
FERRUM_LOG=*,-browser                # everything but Chrome's output
FERRUM_LOG=*,-Network.*,-Target.*    # leave out CDP messages whose method matches
FERRUM_LOG=Page.*,Runtime.evaluate   # only CDP messages whose method matches
FERRUM_LOG=0                         # nothing, even with :logger
```

Items with a dot are CDP method patterns, a leading `-` leaves things out and wins over the rest, and a response is
kept or dropped with the command it answers. Without `FERRUM_LOG`, `:logger` gets everything. `FERRUM_DEBUG` still
works as `FERRUM_LOG=*`, but is deprecated.

`FERRUM_LOG_FORMAT` picks how CDP messages look. `json` writes each message as JSON alone, one per line and never
colored, for tools such as `jq`. `annotated` puts the command id and method in front of each CDP message, one line
each, and gives a response the method of its command and how long the answer took. Params, results and events stay
whole JSON:

```
▶ 1.623 #23 Page.navigate {"url":"http://127.0.0.1:5000/console_log"} @4E470240
    ◀ 1.637 #23 Page.navigate 14ms {"frameId":"325D8B09…","loaderId":"64738D2F…"} @4E470240
    ◀ 1.640 Runtime.consoleAPICalled {"type":"warning","args":[{"type":"string","value":"hey"}],…} @4E470240
```

Without `FERRUM_LOG_FORMAT`, lines look as they always have, `▶ 1.623 {"id":23,"method":"Page.navigate",...}`.

Written to a terminal, lines are colored with the basic ANSI colors, which follow the terminal's light or dark theme:
arrows are colored by kind (sent, response, error, event), methods are bold and times dimmed. The text stays the
same, and files, pipes, `StringIO` and `Logger`s get it without colors, as does a terminal when `NO_COLOR` is set.
`FERRUM_LOG_COLOR=always` or `never` overrides both.

A `Logger` gets every line at debug level, with `ferrum:protocol` or `ferrum:browser` as program name, and nothing is
built when its level is higher.

Console messages aren't logged, subscribe to them with [`page.on(:console)`](/docs/ferrum/javascript#console) and
write them wherever you like.

Chrome's output is also kept when nothing is logged: `browser.process.output.lines` holds its last 100 lines, and
`ProcessTimeoutError#output` has them when Chrome doesn't start.

## The crashpad handler

Chrome starts two `chrome_crashpad_handler` processes per browser on Linux. Their only job is to collect and upload
crash reports, which no automated browser has any use for, but **Ferrum does not disable them**, because there is no
safe way to.

Handlers Chrome starts on Linux:

| Chrome | `--headless` | `--headless=new` | headful |
|---|---|---|---|
| 127 and older | 0 | 2 | 2 |
| 128 and newer | 2 | 2 | 2 |

New headless always starts them. What changed in 128 is what bare `--headless` *means*: before it, that selected old
headless, a separate lightweight shell with no crash handler; from 128 on it selects new headless, which is full
Chrome. Headful has always behaved like new headless.

### No flag turns them off safely

| Flag | What it does |
|---|---|
| `--disable-breakpad` | Stops crash *reporting*, not the handler process |
| `--disable-crash-reporter` | Same |
| `--no-crashpad` | Not a Chromium switch at all, so Chrome ignores it |
| `--disable-crashpad-for-testing` | Real, and it does stop them — but it breaks the browser |

:::danger
Do not pass `--disable-crashpad-for-testing`. It is named `for-testing` because it is meant for Chromium's own test
harness, where the process tree is fully controlled. In a normally launched browser, child processes die at startup
with `Crashing due to FD ownership violation`, and the network service crash-loops.

The failure is near-invisible: the browser process survives, so it starts normally and CDP answers every command.
There is simply no network service behind it, so every navigation returns `net::ERR_ABORTED` and the document stays
`about:blank`.
:::

### Operating system differences

On macOS one handler starts rather than two, and it exits when the browser does, so nothing accumulates.

It is also invisible to `pstree`, because it double-forks and reparents to launchd and is therefore never a
descendant of the process that started Chrome. Look for it globally instead:

```console
$ ps -Ao pid=,ppid=,comm= | grep crashpad
13270     1 .../Helpers/chrome_crashpad_handler
```

`ppid` is `1`, and the pid usually lands just after Chrome's own.

### Why this matters most in Docker

The handler is harmless outside a container. It is not in Chrome's process group, so the signal Ferrum sends on
teardown never reaches it — and does not need to: it watches the browser and exits by itself once Chrome is gone.
What is left behind is an exit status, and because the handler double-forks away from Chrome its parent is pid 1.
Collecting it is PID 1's job which doesn't exist in a container, so the handlers pile up as `<defunct>` entries.
See [Docker](/docs/ferrum/docker).

## Examples

```ruby
# Run in headful mode with custom window size
Ferrum::Browser.new(headless: false, window_size: [1920, 1080])

# Connect to an existing Chrome instance
Ferrum::Browser.new(url: "http://localhost:9222")

# Enable JavaScript error raising
Ferrum::Browser.new(js_errors: true)

# Set custom timeout and slowmo for debugging
Ferrum::Browser.new(timeout: 10, slowmo: 0.5)

# Use custom Chrome binary
Ferrum::Browser.new(browser_path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")

# Add custom browser options
Ferrum::Browser.new(browser_options: { "disable-web-security" => nil })
```
