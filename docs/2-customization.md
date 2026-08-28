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
      source code to be preloaded into the browser e.g.:
      `["/path/to/script.js", { source: "window.secret = 'top'" }]`
    * `:logger` (Object responding to `puts`) - When present, debug output is
      written to this object.
    * `:slowmo` (Integer | Float) - Set a delay in seconds to wait before sending command.
      Useful companion of headless option, so that you have time to see changes.
    * `:timeout` (Numeric) - The number of seconds we'll wait for a response when
      communicating with browser. Default is 5.
    * `:js_errors` (Boolean) - When true, JavaScript errors get re-raised in Ruby.
    * `:pending_connection_errors` (Boolean) - Raise `PendingConnectionsError` when main frame is still waiting
      for slow responses and timeout is reached. Default is false.
    * `:browser_name` (Symbol) - `:chrome` by default, only experimental support
      for `:firefox` for now.
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

## The crashpad handler

Ferrum passes `--disable-crashpad-for-testing` by default, so Chrome does not start `chrome_crashpad_handler` on
Linux. Its only job is to collect and upload crash reports, which no automated browser has any use for, and Chrome
starts two of them per browser.

Handlers Chrome starts on Linux, without the flag:

| Chrome | `--headless` | `--headless=new` | headful |
|---|---|---|---|
| 127 and older | 0 | 2 | 2 |
| 128 and newer | 2 | 2 | 2 |

New headless always starts them. What changed in 128 is what bare `--headless` *means*: before it, that
selected old headless, a separate lightweight shell with no crash handler; from 128 on it selects new headless,
which is full Chrome. Headful has always behaved like new headless.

### What the flag does

`--disable-crashpad-for-testing` turns any of those `2`s into `0`, on Chrome 128 and newer.

The switch was added in 128 — the same release that made bare `--headless` start handlers.

Three flags that look like they should do this, and don't:

| Flag | Why not |
|---|---|
| `--disable-breakpad` | Stops crash *reporting*, not the handler process |
| `--disable-crash-reporter` | Same |
| `--no-crashpad` | Not a Chromium switch at all, so Chrome ignores it |

### Operating system differences

On Linux the flag works: two handlers per browser without it, none with it.

On macOS it does not. One handler starts whether the flag is passed — a single process rather than two — and
it exits when the browser does, so nothing accumulates.

It is also invisible to `pstree`, because it double-forks and reparents to launchd and is therefore never a
descendant of the process that started Chrome. Look for it globally instead:

```console
$ ps -Ao pid=,ppid=,comm= | grep crashpad
13270     1 .../Helpers/chrome_crashpad_handler
```

`ppid` is `1`, and the pid usually lands just after Chrome's own.

Why the switch is ignored is unknown. The handler is started with
`--database=~/Library/Application Support/Google/Chrome/Crashpad` — the default profile, not the `--user-data-dir`
Ferrum passes — which suggests it is launched from framework-level initialization rather than from that browser's
command line, but that has not been confirmed.

### Why this matters most in Docker

The handler does not pose a problem when running outside a container. It is deliberately independent of Chrome's process group,
so the signal Ferrum sends during teardown cannot and does not need to terminate it. Instead, the handler monitors the browser
process and cleans itself up once Chrome exits. This behavior was verified by sending both `TERM` and `KILL` to the process group,
as well as `KILL` and `SIGUSR1` directly to the browser PID. In every case, the handler detected the browser exit and terminated
on its own within a second.

Since the handler is detached from Chrome through a double fork, it is reparented to PID 1.
The system’s init process—typically systemd or launchd takes care of reaping it automatically,
so there is no visible leftover process or manual cleanup required.

In a container your own process is usually pid 1, and it does not wait on children it never spawned. Nothing reaps
the handlers, so every browser leaves two more `<defunct>` entries behind, and they are never reclaimed.
**It accumulates, until the process table fills up.**

Leaving the flag on is the direct fix — no handler starts, so there is nothing to reap. Running the container with an
init (`docker run --init`, `init: true` in Compose, or tini as the entrypoint) also handles it, and is worth doing
regardless, since everything else in the image has the same problem.

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
