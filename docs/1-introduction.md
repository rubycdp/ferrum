---
sidebar_position: 1
---

# Introduction

Ferrum is a high-level API to control Chrome in Ruby.

![Ferrum Logo](https://raw.githubusercontent.com/rubycdp/ferrum/main/logo.svg?sanitize=true)

It is Ruby clean and high-level API to Chrome. Runs headless by default, but you
can configure it to run in a headful mode. All you need is Ruby and [Chrome](https://www.google.com/chrome/) or [Chromium](https://www.chromium.org/).
Ferrum connects to the browser by [CDP protocol](https://chromedevtools.github.io/devtools-protocol/) and  there's _no_
Selenium/WebDriver/ChromeDriver dependency. The emphasis was made on a raw CDP
protocol because Chrome allows you to do so many things that are barely
supported by WebDriver because it should have consistent design with other
browsers.

## Installation

There's no official Chrome or Chromium package for Linux don't install it this
way because it's either outdated or unofficial, both are bad. Download it from
official source for [Chrome](https://www.google.com/chrome/) or [Chromium](https://www.chromium.org/getting-involved/download-chromium).
Chrome binary should be in the `PATH` or `BROWSER_PATH` and you can pass it as an
option to browser instance see `:browser_path` in
[Customization](/docs/ferrum/customization).

Add this to your `Gemfile` and run `bundle install`.

``` ruby
gem "ferrum"
```

## Docker

:::note
When running in docker as root
:::

```ruby
Ferrum::Browser.new(dockerize: true)
```

Essentially it just sets CLI flags for a browser to make it start. On CI, you can just set `FERRUM_CHROME_DOCKERIZE=true` environment variable, and it will be
passed to all browser instances.

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

## Clean Up

Closes browser tabs opened by the `Browser` instance.

```ruby
# connect to a long-running Chrome process
browser = Ferrum::Browser.new(url: "http://localhost:9222")

browser.go_to("https://github.com/")

# clean up, lest the tab stays there hanging forever
browser.reset

browser.quit
```

## Thread safety

Ferrum is fully thread-safe. You can create one browser or a few as you wish and
start playing around using threads. Example below shows how to create a few pages
which share the same context. Context is similar to an incognito profile but you
can have more than one, think of it like it's independent browser session:

```ruby
browser = Ferrum::Browser.new
context = browser.contexts.create

t1 = Thread.new(context) do |c|
  page = c.create_page
  page.go_to("https://www.google.com/search?q=Ruby+headless+driver+for+Capybara")
  page.screenshot(path: "t1.png")
end

t2 = Thread.new(context) do |c|
  page = c.create_page
  page.go_to("https://www.google.com/search?q=Ruby+static+typing")
  page.screenshot(path: "t2.png")
end

t1.join
t2.join

context.dispose
browser.quit
```

or you can create two independent contexts:

```ruby
browser = Ferrum::Browser.new

t1 = Thread.new(browser) do |b|
  context = b.contexts.create
  page = context.create_page
  page.go_to("https://www.google.com/search?q=Ruby+headless+driver+for+Capybara")
  page.screenshot(path: "t1.png")
  context.dispose
end

t2 = Thread.new(browser) do |b|
  context = b.contexts.create
  page = context.create_page
  page.go_to("https://www.google.com/search?q=Ruby+static+typing")
  page.screenshot(path: "t2.png")
  context.dispose
end

t1.join
t2.join

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
