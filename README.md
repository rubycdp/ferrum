# Ferrum - fearless Ruby Chrome/Chromium driver

As simple as Puppeteer, though even simpler. It is Ruby clean and high-level API
to Chrome/Chromium through the DevTools Protocol. Runs headless by default,
but you can configure it to run in a non-headless mode.

Navigate to `example.com` and save a screenshot:

```ruby
browser = Ferrum::Browser.new
browser.goto("https://example.com")
browser.screenshot(path: "example.png")
browser.quit
```

Interact with a page:

```ruby
browser = Ferrum::Browser.new
browser.goto("https://google.com")
input = browser.at_xpath("//div[@id='searchform']/form//input[@type='text']")
input.focus.type("Ruby headless driver for Capybara", :Enter)
browser.at_css("a > h3").text # => "machinio/cuprite: Headless Chrome driver for Capybara - GitHub"
browser.quit
```

The README will be updated soon. Meanwhile take a look at specs.
