---
sidebar_position: 12
---

# Headers

`page.headers`

#### get : `Hash`

Get all headers

#### set(headers) : `Boolean`

Set given headers. Eventually clear all headers and set given ones.

* headers `Hash` key-value pairs for example `"User-Agent" => "Browser"`

`User-Agent` and `Accept-Language` also change what `navigator` reports, through
[network.emulate](https://github.com/rubycdp/ferrum#network). Other headers leave it alone, and `set` brings back the
user agent or language that an earlier `set` put and the new headers no longer have.

#### add(headers) : `Boolean`

Adds given headers to already set ones.

* headers `Hash` key-value pairs for example `"Referer" => "http://example.com"`

#### clear : `Boolean`

Clear all headers.
