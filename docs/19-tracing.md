---
sidebar_position: 19
---

# Tracing

You can use `tracing.record` to create a trace file which can be opened in Chrome DevTools or
[timeline viewer](https://chromedevtools.github.io/timeline-viewer/).

```ruby
page.tracing.record(path: "trace.json") do
  page.go_to("https://www.google.com")
end
```

#### tracing.record(\*\*options) : `String`

Accepts block, records trace and by default returns trace data from `Tracing.tracingComplete` event as output. When
`path` is specified returns `true` and stores trace data into file.

* options `Hash`
    * :path `String` save data on the disk, `nil` by default
    * :encoding `Symbol` `:base64` | `:binary` encode output as Base64 or plain text. `:binary` by default
    * :timeout `Float` wait until file streaming finishes in the specified time or raise error, defaults to `nil`
    * :screenshots `Boolean` capture screenshots in the trace, `false` by default
    * :trace_config `Hash<String, Object>` config for
      [trace](https://chromedevtools.github.io/devtools-protocol/tot/Tracing/#type-TraceConfig), for categories
      see [getCategories](https://chromedevtools.github.io/devtools-protocol/tot/Tracing/#method-getCategories),
      only one trace config can be active at a time per browser.
