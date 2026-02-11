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

#### add(headers) : `Boolean`

Adds given headers to already set ones.

* headers `Hash` key-value pairs for example `"Referer" => "http://example.com"`

#### clear : `Boolean`

Clear all headers.
