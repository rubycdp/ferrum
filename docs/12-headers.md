---
sidebar_position: 12
---

# Headers

`page.headers`

#### get : `Hash`

Get all headers

#### set(headers)

Set given headers. Eventually clear all headers and set given ones.

* headers `Hash` key-value pairs for example `"User-Agent" => "Browser"`

`User-Agent` and `Accept-Language` also change what `navigator` reports, through
[network.emulate](https://github.com/rubycdp/ferrum#network). Other headers leave it alone, and `set` and `clear` bring
back the browser's user agent or language once the header that changed it is gone. This is deprecated: from 0.22 the
two headers are only sent with requests, like any other, and `navigator` and the client hints stay as they are. Use
`network.emulate(user_agent:, accept_language:)` to override both the header and what the page reports.

#### add(headers)

Adds given headers to already set ones.

* headers `Hash` key-value pairs for example `"Referer" => "http://example.com"`

#### clear

Clear all headers, and the user agent or language they set.
