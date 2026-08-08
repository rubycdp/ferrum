---
sidebar_position: 15
---

# Frames

Frames allow you to work with iframes and nested documents within a page. Each frame has its own execution context and can be interacted with independently.

#### frames : `Array[Frame] | []`

Returns all the frames current page have.

```ruby
page.go_to("https://www.w3schools.com/tags/tag_frame.asp")
page.frames # =>
# [
#   #<Ferrum::Frame @id="C6D104CE454A025FBCF22B98DE612B12" @parent_id=nil @name=nil @state=:stopped_loading @execution_id=1>,
#   #<Ferrum::Frame @id="C09C4E4404314AAEAE85928EAC109A93" @parent_id="C6D104CE454A025FBCF22B98DE612B12" @state=:stopped_loading @execution_id=2>,
#   #<Ferrum::Frame @id="2E9C7F476ED09D87A42F2FEE3C6FBC3C" @parent_id="C6D104CE454A025FBCF22B98DE612B12" @state=:stopped_loading @execution_id=3>,
#   ...
# ]
```

#### main_frame : `Frame`

Returns page's main frame, the top of the tree and the parent of all frames.

#### frame_by(\*\*options) : `Frame | nil`

Find frame by given options.

* options `Hash`
    * :id `String` - Unique frame's id that browser provides
    * :name `String` - Frame's name if there's one

```ruby
page.frame_by(id: "C6D104CE454A025FBCF22B98DE612B12")
```

## Frame

## Frame

#### id : `String`

Frame's unique id.

#### parent_id : `String | nil`

Parent frame id if this one is nested in another one.

#### parent : `Frame | nil`

Parent frame if this one is nested in another one.

#### frame_element : `Node | nil`

Returns the element in which the window is embedded.

#### execution_id : `Integer`

Execution context id which is used by JS, each frame has its own context in
which JS evaluates.

#### name : `String | nil`

If frame was given a name it should be here.

#### state : `Symbol | nil`

One of the states frame's in:

* `:started_loading`
* `:navigated`
* `:stopped_loading`

#### url : `String`

Returns current frame's location href.

```ruby
page.go_to("https://developer.mozilla.org/en-US/docs/Web/HTML/Element/iframe")
frame = page.frames[1]
frame.url # => https://interactive-examples.mdn.mozilla.net/pages/tabbed/iframe.html
```

#### title

Returns current frame's title.

```ruby
page.go_to("https://developer.mozilla.org/en-US/docs/Web/HTML/Element/iframe")
frame = page.frames[1]
frame.title # => HTML Demo: <iframe>
```

#### main? : `Boolean`

If current frame is the main frame of the page (top of the tree).

```ruby
page.go_to("https://www.w3schools.com/tags/tag_frame.asp")
frame = page.frame_by(id: "C09C4E4404314AAEAE85928EAC109A93")
frame.main? # => false
```

#### current_url : `String`

Returns current frame's top window location href.

```ruby
page.go_to("https://www.w3schools.com/tags/tag_frame.asp")
frame = page.frame_by(id: "C09C4E4404314AAEAE85928EAC109A93")
frame.current_url # => "https://www.w3schools.com/tags/tag_frame.asp"
```

#### current_title : `String`

Returns current frame's top window title.

```ruby
page.go_to("https://www.w3schools.com/tags/tag_frame.asp")
frame = page.frame_by(id: "C09C4E4404314AAEAE85928EAC109A93")
frame.current_title # => "HTML frame tag"
```

#### body : `String`

Returns current frame's html.

```ruby
page.go_to("https://www.w3schools.com/tags/tag_frame.asp")
frame = page.frame_by(id: "C09C4E4404314AAEAE85928EAC109A93")
frame.body # => "<html><head></head><body></body></html>"
```

#### doctype

Returns current frame's doctype.

```ruby
page.go_to("https://www.w3schools.com/tags/tag_frame.asp")
page.main_frame.doctype # => "<!DOCTYPE html>"
```

#### content = html

Sets a content of a given frame.

* html `String`

```ruby
page.go_to("https://developer.mozilla.org/en-US/docs/Web/HTML/Element/iframe")
frame = page.frames[1]
frame.body # <html lang="en"><head><style>body {transition: opacity ease-in 0.2s; }...
frame.content = "<html><head></head><body><p>lol</p></body></html>"
frame.body # => <html><head></head><body><p>lol</p></body></html>
```

## Example

You can access a frame and then use finders to locate elements within that frame:

```ruby
page.go_to("https://example.com/page-with-iframe")
frame = page.at_xpath("//iframe").frame # => Frame
frame.at_css("//a[text() = 'Log in']") # => Node
```
