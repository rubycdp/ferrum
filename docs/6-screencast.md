---
sidebar_position: 6
---

# Screencast

#### start_screencast(\*\*options) \{ |data, metadata, session_id| ... \}

Starts sending frames to record screencast to the given block.

* options `Hash`
  * :format `Symbol` `:jpeg` | `:png` The format the image should be returned in.
  * :quality `Integer` The image quality. **Note:** 0-100 works for JPEG only.
  * :max_width `Integer` Maximum screencast frame width.
  * :max_height `Integer` Maximum screencast frame height.
  * :every_nth_frame `Integer` Send every n-th frame.

* Block inputs:
  * data `String` Base64-encoded compressed image.
  * metadata `Hash` Screencast frame metadata.
    * "offsetTop" `Integer` Top offset in DIP.
    * "pageScaleFactor" `Integer` Page scale factor.
    * "deviceWidth" `Integer` Device screen width in DIP.
    * "deviceHeight" `Integer` Device screen height in DIP.
    * "scrollOffsetX" `Integer` Position of horizontal scroll in CSS pixels.
    * "scrollOffsetY" `Integer` Position of vertical scroll in CSS pixels.
    * "timestamp" `Float` (optional) Frame swap timestamp in seconds since Unix epoch.
  * session_id `Integer` Frame number.

```ruby
require "base64"

page.go_to("https://apple.com/ipad")

page.start_screencast(format: :jpeg, quality: 75) do |data, metadata|
  timestamp = (metadata["timestamp"] * 1000).to_i
  File.binwrite("image_#{timestamp}.jpg", Base64.decode64(data))
end

sleep 10

page.stop_screencast
```

> ### 📝 NOTE
>
> Chrome only sends new frames while page content is changing. For example, if
> there is an animation or a video on the page, Chrome sends frames at the rate
> requested. On the other hand, if the page is nothing but a wall of static text,
> Chrome sends frames while the page renders. Once Chrome has finished rendering
> the page, it sends no more frames until something changes (e.g., navigating to
> another location).

#### stop_screencast

Stops sending frames.
