---
sidebar_position: 9
---

# Proxy

You can set a proxy with a `:proxy` option:

```ruby
Ferrum::Browser.new(proxy: { host: "x.x.x.x", port: "8800", user: "user", password: "pa$$" })
```

`:bypass` can specify semi-colon-separated list of hosts for which proxy shouldn't be used:

```ruby
Ferrum::Browser.new(proxy: { host: "x.x.x.x", port: "8800", bypass: "*.google.com;*foo.com" })
```

In general passing a proxy option when instantiating a browser results in a browser running with proxy command line
flags, so that it affects all pages and contexts. You can create a page in a new context which can use its own proxy
settings:

```ruby
browser = Ferrum::Browser.new

browser.create_page(proxy: { host: "x.x.x.x", port: 31337, user: "user", password: "password" }) do |page|
  page.go_to("https://api.ipify.org?format=json")
  page.body # => "x.x.x.x"
end

browser.create_page(proxy: { host: "y.y.y.y", port: 31337, user: "user", password: "password" }) do |page|
  page.go_to("https://api.ipify.org?format=json")
  page.body # => "y.y.y.y"
end
```
