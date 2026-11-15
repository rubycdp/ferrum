---
sidebar_position: 16
---

# Dialogs

#### accept(text)

Accept dialog with given text or default prompt if applicable

* text `String`

#### dismiss

Dismiss dialog

Callbacks run in the order they were added and the rest are skipped once one accepts or dismisses the dialog. A dialog
nobody handled is accepted with a warning.

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
