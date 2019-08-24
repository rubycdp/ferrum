# Ferrum - fearless Ruby headless Chrome driver (as simple as Puppeteer, though even simpler).

Navigate to `example.com` and save a screenshot:

```ruby
browser = Ferrum::Browser.new
browser.goto("https://example.com")
browser.screenshot(path: "example.png")
browser.quit
```

## Links
https://medium.com/@aslushnikov/automating-clicks-in-chromium-a50e7f01d3fb
https://developer.mozilla.org/en-US/docs/Web/API/Intersection_Observer_API
https://github.com/machinio/cuprite/commit/9b1041dd6cd954e0b40b17bc74824e7a3a3ff3f4
