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

#### wait(timeout)

Waits until the download is finished.

```ruby
page.go_to("http://localhost/attachment.pdf")
page.downloads.wait
```

or

```ruby
page.go_to("http://localhost/page")
page.downloads.wait { page.at_css("#download").click }
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
