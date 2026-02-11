---
sidebar_position: 16
---

# Dialogs

#### accept(text)

Accept dialog with given text or default prompt if applicable

* text `String`

#### dismiss

Dismiss dialog

```ruby
page.on(:dialog) do |dialog|
  if dialog.match?(/bla-bla/)
    dialog.accept
  else
    dialog.dismiss
  end
end
page.go_to("https://google.com")
```
