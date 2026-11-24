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

`User-Agent` and `Accept-Language` are only sent with requests, like any other header, `navigator` and the client
hints stay as they are. Use [network.emulate(user_agent:, accept_language:)](/docs/ferrum/network)
to override both the header and what the page reports.

#### add(headers)

Adds given headers to already set ones.

* headers `Hash` key-value pairs for example `"Referer" => "http://example.com"`

#### clear

Clear all headers, and the user agent or language they set.
