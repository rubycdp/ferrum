---
sidebar_position: 11
---

# Cookies

`page.cookies`

#### all : `Hash<String, Cookie>`

Returns cookies hash

```ruby
page.cookies.all # => {"NID"=>#<Ferrum::Cookies::Cookie:0x0000558624b37a40 @attributes={"name"=>"NID", "value"=>"...", "domain"=>".google.com", "path"=>"/", "expires"=>1583211046.575681, "size"=>178, "httpOnly"=>true, "secure"=>false, "session"=>false}>}
```

#### \[\](value) : `Cookie`

Returns cookie

* value `String`

```ruby
page.cookies["NID"] # => <Ferrum::Cookies::Cookie:0x0000558624b67a88 @attributes={"name"=>"NID", "value"=>"...", "domain"=>".google.com", "path"=>"/", "expires"=>1583211046.575681, "size"=>178, "httpOnly"=>true, "secure"=>false, "session"=>false}>
```

#### set(value) : `Boolean`

Sets a cookie

* value `Hash`
  * :name `String`
  * :value `String`
  * :domain `String`
  * :expires `Integer`
  * :samesite `String`
  * :httponly `Boolean`

```ruby
page.cookies.set(name: "stealth", value: "omg", domain: "google.com") # => true
```

* value `Cookie`

```ruby
nid_cookie = page.cookies["NID"] # => <Ferrum::Cookies::Cookie:0x0000558624b67a88>
page.cookies.set(nid_cookie) # => true
```

#### remove(\*\*options) : `Boolean`

Removes given cookie

* options `Hash`
  * :name `String`
  * :domain `String`
  * :url `String`

```ruby
page.cookies.remove(name: "stealth", domain: "google.com") # => true
```

#### clear : `Boolean`

Removes all cookies for current page

```ruby
page.cookies.clear # => true
```

#### store(path) : `Boolean`

Stores all cookies of current page in a file.

```ruby
# Cookies are saved into cookies.yml
page.cookies.store # => 15657
```

#### load(path) : `Boolean`

Loads all cookies from the file and sets them for current page.

```ruby
# Cookies are loaded from cookies.yml
page.cookies.load # => true
```
