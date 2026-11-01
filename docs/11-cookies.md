---
sidebar_position: 11
---

# Cookies

Cookies belong to a [context](https://github.com/rubycdp/ferrum#contexts), and every page in it shares them.
`context.cookies` has all of them, whatever their domain. `browser.cookies` is the cookies of the default context.
`page.cookies` narrows them down to what the page sees: the cookies sent to its URL and the URLs of its frames.

```ruby
# After logging in on example.com through sso.example.com
browser.cookies.map(&:name) # => ["session", "sso_token"]
browser.page.cookies.map(&:name) # => ["session"]
```

## Context cookies

`browser.cookies`, `context.cookies`

#### each : `Enumerator<Cookie>`

All cookies in the context. Cookies are `Enumerable`, so `to_a`, `select`, `map` and the rest work too.

```ruby
browser.cookies.to_a # => [#<Ferrum::Cookies::Cookie:0x0000558624b37a40 @attributes={"name"=>"NID", "value"=>"...", "domain"=>".google.com", "path"=>"/", "expires"=>1583211046.575681, "size"=>178, "httpOnly"=>true, "secure"=>false, "session"=>false}>]
browser.cookies.select { |cookie| cookie.domain == ".google.com" }
```

#### all : `Hash<String, Cookie>`

Deprecated, will be removed in 0.22. Cookies keyed by name, so of the cookies sharing a name only one is kept. Use
`to_a`, or `map(&:name)` for the names.

#### \[\](name, domain: `String`, path: `String`) : `Cookie` | `nil`

The first cookie with the given name. A name can be used by several cookies, on different domains or paths, `domain`
and `path` pick one of them. Both are exact, a cookie sent to every subdomain has a domain with a leading dot.

* name `String`
* domain `String`
* path `String`

```ruby
browser.cookies["NID"] # => <Ferrum::Cookies::Cookie:0x0000558624b67a88 @attributes={"name"=>"NID", "value"=>"...", "domain"=>".google.com", "path"=>"/", "expires"=>1583211046.575681, "size"=>178, "httpOnly"=>true, "secure"=>false, "session"=>false}>
browser.cookies["id", domain: "www.example.com", path: "/app"]
```

#### set(value) : `true`

Sets a cookie, for the `:base_url` host unless `:domain` or `:url` is given.

* value `Hash`
  * :name `String`
  * :value `String`
  * :domain `String`
  * :url `String`
  * :path `String`
  * :expires `Integer`
  * :samesite `String`
  * :httponly `Boolean`
  * :secure `Boolean`

```ruby
browser.cookies.set(name: "stealth", value: "omg", domain: "google.com") # => true
```

* value `Cookie`

```ruby
nid_cookie = browser.cookies["NID"] # => <Ferrum::Cookies::Cookie:0x0000558624b67a88>
browser.cookies.set(nid_cookie) # => true
```

#### remove(\*\*options) : `true`

Removes the cookies with the given name, on the exact domain, the `:base_url` host by default, or the ones sent to the
URL.

* options `Hash`
  * :name `String`
  * :domain `String`
  * :url `String`
  * :path `String`

```ruby
browser.cookies.remove(name: "stealth", domain: "google.com") # => true
browser.cookies.remove(name: "sso_token", url: "https://sso.example.com") # => true
```

#### clear : `true`

Removes all cookies in the context.

```ruby
browser.cookies.clear # => true
```

#### store(path) : `Integer`

Stores all cookies in the context in a file, `cookies.yml` by default.

```ruby
browser.cookies.store # => 15657
```

#### load(path) : `true`

Loads the cookies from a file, `cookies.yml` by default, and sets them in the context.

```ruby
browser.cookies.load # => true
```

## Page cookies

`page.cookies`

#### each(urls: `Array<String>`) : `Enumerator<Cookie>`

The cookies sent to the page's URL and the URLs of its frames, or to the given URLs. Nothing before the page has
loaded a URL. `all` is deprecated here too.

```ruby
page.cookies.map(&:name) # => ["session"]
page.cookies.each(urls: ["https://sso.example.com"]).map(&:name) # => ["sso_token"]
```

#### \[\](name, domain: `String`, path: `String`) : `Cookie` | `nil`

The page's first cookie with the given name, narrowed down like the context's.

```ruby
page.cookies["NID"] # => <Ferrum::Cookies::Cookie:0x0000558624b67a88>
```

#### set(value) : `Boolean`

Sets a cookie, takes the same options as the context's `set`. Without `:domain` or `:url` it's set for the page's host,
or the `:base_url` host before the page has loaded anything.

```ruby
page.cookies.set(name: "stealth", value: "omg") # => true
```

#### remove(\*\*options) : `true`

Removes the cookies with the given name, on the page's host unless `:domain` or `:url` is given.

```ruby
page.cookies.remove(name: "stealth") # => true
```

#### clear : `true`

Removes the page's cookies, the ones `each` yields. Cookies on other domains stay.

```ruby
page.cookies.clear # => true
```
