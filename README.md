# Ferrum - high-level API to control Chrome in Ruby

## [Documentation](https://docs.rubycdp.com/docs/ferrum/introduction)

<img align="right"
     width="160" height="160"
     alt="Ferrum logo"
     src="https://raw.githubusercontent.com/rubycdp/ferrum/main/logo.svg?sanitize=true">

It is Ruby clean and high-level API to Chrome. Runs headless by default, but you
can configure it to run in a headful mode. All you need is Ruby and [Chrome](https://www.google.com/chrome/) or [Chromium](https://www.chromium.org/).
Ferrum connects to the browser by [CDP protocol](https://chromedevtools.github.io/devtools-protocol/) and  there's _no_
Selenium/WebDriver/ChromeDriver dependency. The emphasis was made on a raw CDP
protocol because Chrome allows you to do so many things that are barely
supported by WebDriver because it should have consistent design with other
browsers.

* [Cuprite](https://github.com/rubycdp/cuprite) is a pure Ruby driver for [Capybara](https://github.com/teamcapybara/capybara) based on Ferrum.
* [Vessel](https://github.com/rubycdp/vessel) high-level web crawling framework based on Ferrum and Mechanize.

<br clear="right">

## Install

There's no official Chrome or Chromium package for Linux don't install it this
way because it's either outdated or unofficial, both are bad. Download it from
official source for [Chrome](https://www.google.com/chrome/) or [Chromium](https://www.chromium.org/getting-involved/download-chromium).
Chrome binary should be in the `PATH` or `BROWSER_PATH` and you can pass it as an
option to browser instance see `:browser_path` in
[Customization](https://docs.rubycdp.com/docs/ferrum/customization).

Add this to your `Gemfile` and run `bundle install`.

``` ruby
gem "ferrum"
```

Or skip installing Chrome and run it in a container with our images, see
[Docker](https://docs.rubycdp.com/docs/ferrum/docker#our-images-recommended):

```shell
docker run --rm -p 3000:3000 ghcr.io/rubycdp/chromium
```

```ruby
browser = Ferrum::Browser.new(url: "http://localhost:3000")
```

## Quick Start

Navigate to a website and save a screenshot:

```ruby
browser = Ferrum::Browser.new
browser.go_to("https://google.com")
browser.screenshot(path: "google.png")
browser.quit
```

When you work with browser instance Ferrum creates and maintains a default page for you, in fact all the methods above
are sent to the `page` instance that is created in the `default_context` of the `browser` instance. You can interact
with a page created manually and this is preferred:

```ruby
browser = Ferrum::Browser.new
page = browser.create_page
page.go_to("https://google.com")
input = page.at_xpath("//input[@name='q']")
input.focus.type("Ruby headless driver for Chrome", :Enter)
page.at_css("a > h3").text # => "rubycdp/ferrum: Ruby Chrome/Chromium driver - GitHub"
browser.quit
```

Evaluate some JavaScript and get full width/height:

```ruby
browser = Ferrum::Browser.new
page = browser.create_page
page.go_to("https://www.google.com/search?q=Ruby+headless+driver+for+Capybara")
width, height = page.evaluate <<~JS
  [document.documentElement.offsetWidth,
   document.documentElement.offsetHeight]
JS
# => [1024, 1931]
browser.quit
```

Pass arguments by name, so the script can use parameters instead of digging
through `arguments[0]`:

```ruby
page.evaluate("a + b", a: 1, b: 2) # => 3
page.evaluate("el.getAttribute(name)", el: page.at_css("a"), name: "href")
```

A script that starts with a function or arrow declaration is used as-is, which
is how you run more than one statement:

```ruby
page.evaluate(<<~JS, a: 1, b: 2)
  function(a, b) {
    const sum = a + b;
    return sum * 3;
  }
JS
```

`await` works directly, and a returned promise is awaited:

```ruby
page.evaluate("await fetch(url).then(r => r.text())", url: "/api")
```

Pass `timeout:` (seconds, defaulting to the page timeout) to bound how long the
script may take before `Ferrum::ScriptTimeoutError` is raised, or `0` to let it
run for as long as it takes. `timeout:` and `args:` are the only reserved
keywords; use `args:` when a JavaScript parameter needs one of those names:

```ruby
page.evaluate("timeout * 2", args: { timeout: 21 }) # => 42
```

Use `#execute` when you only want the side effects, `#evaluate_handle` when you
want to keep a value in the browser and pass it back in later, and
`Ferrum::Node#evaluate` to run a script with `this` bound to an element:

```ruby
page.execute("window.scrollBy(0, 100)") # => true

list = page.evaluate_handle("document.querySelectorAll('li')")
page.evaluate("Array.from(nodes).map(n => n.textContent)", nodes: list)

page.at_css("input").evaluate("this.value")
```

Coming from 0.20 or earlier? See
[upgrading to 0.21](docs/13-javascript.md#upgrading-to-021).

Do any mouse movements you like:

```ruby
# Trace a 100x100 square
browser = Ferrum::Browser.new
page = browser.create_page
page.go_to("https://google.com")
page.mouse
  .move(x: 0, y: 0)
  .down
  .move(x: 0, y: 100)
  .move(x: 100, y: 100)
  .move(x: 100, y: 0)
  .move(x: 0, y: 0)
  .up

browser.quit
```

## Development

After checking out the repo, run `bundle install` to install dependencies.

Then, run `bundle exec rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will
allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the
version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version,
push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).


## Contributing

Bug reports and pull requests are welcome on [GitHub](https://github.com/rubycdp/ferrum).

## License

The gem is available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT).
