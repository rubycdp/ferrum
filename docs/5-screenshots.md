---
sidebar_position: 5
---

# Screenshots

#### screenshot(\*\*options) : `String` | `Integer`

Saves screenshot on a disk or returns it as base64.

* options `Hash`
  * :path `String` to save a screenshot on the disk. `:encoding` will be set to
    `:binary` automatically
  * :encoding `Symbol` `:base64` | `:binary` you can set it to return image as
    Base64
  * :format `String` "jpeg" ("jpg") | "png" | "webp"
  * :quality `Integer` 0-100 works for jpeg only
  * :full `Boolean` whether you need full page screenshot or a viewport
  * :selector `String` css selector for given element, optional
  * :area `Hash` area for screenshot, optional
    * :x `Integer`
    * :y `Integer`
    * :width `Integer`
    * :height `Integer`
  * :scale `Float` zoom in/out
  * :background_color `Ferrum::RGBA.new(0, 0, 0, 0.0)` to have specific background color

```ruby
page.go_to("https://google.com/")
# Save on the disk in PNG
page.screenshot(path: "google.png") # => 134660
# Save on the disk in JPG
page.screenshot(path: "google.jpg") # => 30902
# Save to Base64 the whole page not only viewport and reduce quality
page.screenshot(full: true, quality: 60, encoding: :base64) # "iVBORw0KGgoAAAANSUhEUgAABAAAAAMACAYAAAC6uhUNAAAAAXNSR0IArs4c6Q...
# Save on the disk with the selected element in PNG
page.screenshot(path: "google.png", selector: "textarea") # => 11340
# Save to Base64 with an area of the page in PNG
page.screenshot(path: "google.png", area: { x: 0, y: 0, width: 400, height: 300 }) # => 54239
# Save with specific background color
page.screenshot(background_color: Ferrum::RGBA.new(0, 0, 0, 0.0))
```

#### pdf(\*\*options) : `String` | `Boolean`

Saves PDF on a disk or returns it as base64.

* options `Hash`
  * :path `String` to save a pdf on the disk. `:encoding` will be set to
    `:binary` automatically
  * :encoding `Symbol` `:base64` | `:binary` you can set it to return pdf as
    Base64
  * :landscape `Boolean` paper orientation. Defaults to false.
  * :scale `Float` zoom in/out
  * :format `symbol` standard paper sizes :letter, :legal, :tabloid, :ledger, :A0, :A1, :A2, :A3, :A4, :A5, :A6

  * :paper_width `Float` set paper width
  * :paper_height `Float` set paper height
  * See other [native options](https://chromedevtools.github.io/devtools-protocol/tot/Page#method-printToPDF) you can pass

```ruby
page.go_to("https://google.com/")
# Save to disk as a PDF
page.pdf(path: "google.pdf", paper_width: 1.0, paper_height: 1.0) # => true
```

#### mhtml(\*\*options) : `String` | `Integer`

Saves MHTML on a disk or returns it as a string.

* options `Hash`
  * :path `String` to save a file on the disk.

```ruby
page.go_to("https://google.com/")
page.mhtml(path: "google.mhtml") # => 87742
```
