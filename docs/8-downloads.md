---
sidebar_position: 8
---

# Downloads

`page.downloads`

#### files `Array<Hash>`

Returns all information about downloaded files as a `Hash`.

```ruby
page.go_to("http://localhost/attachment.pdf")
page.downloads.files # => [{"frameId"=>"E3316DF1B5383D38F8ADF7485005FDE3", "guid"=>"11a68745-98ac-4d54-9b57-9f9016c268b3", "url"=>"http://localhost/attachment.pdf", "suggestedFilename"=>"attachment.pdf", "totalBytes"=>4911, "receivedBytes"=>4911, "state"=>"completed"}]
```

#### await_download(timeout: 5) { } : `Hash` | `nil`

Runs the block and waits for the download it starts to finish. Returns the download, like an entry of `files`, its
`"state"` is `"completed"` or `"canceled"`. Returns `nil` if it doesn't finish within `timeout`, 5 seconds by
default. `await_download!` raises `Ferrum::TimeoutError` instead. Also on `page`.

```ruby
page.go_to("http://localhost/page")
page.await_download { page.at_css("#download").click } # => {"suggestedFilename"=>"attachment.pdf", "state"=>"completed", ...}
page.await_download! { page.go_to("http://localhost/attachment.pdf") }
```

#### set_behavior(\*\*options)

Sets behavior in case of file to be downloaded.

* options `Hash`
    * :save_path `String` absolute path of where to store the file
    * :behavior `Symbol` `deny | allow | allowAndName | default`, `allow` by default

```ruby
page.go_to("https://example.com/")
page.downloads.set_behavior(save_path: "/tmp", behavior: :allow)
```
