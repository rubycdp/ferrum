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
    * `:flatten` (Boolean) - Use one websocket connection to the browser and all the pages in flatten mode.
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
    * `:host` (String) - Remote debugging address for headless Chrome.
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
