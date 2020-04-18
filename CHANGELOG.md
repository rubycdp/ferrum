## [0.2.1] - (Sep 5, 2019) ##

### Added

- handle `EOFError/Errno::ECONNRESET/Errno::EPIPE` errors with rescue

- description options of `Customization` in README

### Changed

- increased Browser::Process::PROCESS_TIMEOUT constant by 1

- `Ferrum::Network::InterceptedRequest#match?` to handle cases for Ruby 2.3 and less
 
## [0.2.0] - (Sep 3, 2019) ##

### Added

- snippet examples of the actions in README

- `Ferrum::Node#focus` - fires the `command` `DOM.focus` on Page instance

- `Ferrum::Node#blur` - evaluates JS: `this.blur()` on Page instance

- `Ferrum::Node#click` - fires the native `click` on Page instance

- usage of `FERRUM_INTERMITTENT_ATTEMPTS` `ENV-var` on the rescue of runtime intermittent error

- implementation's of `Ferrum::Page::DOM#xpath` & `Ferrum::Page::DOM#at_xpath` 

- `Ferrum.with_attempts` - retry attempt with the sleep on the block passed as an argument

- `Ferrum::NoExecutionContextError` - raises when there's no `context` available

- `Ferrum::Node#attribute` - evaluates JS: `this.getAttribute` with passed `name`

- `Ferrum::Mouse` - dedicated class of `mouse` actions: `click/down/up/move`

- `Ferrum::Browser#mouse` - delegated actions to `Ferrum::Mouse` instance extracted from `Ferrum::Page::Input`

- `Ferrum::Page::Input#find_position` - usage of `DOM.getContentQuads` to find position of node by `top/left`

- `Ferrum::Keyboard` - dedicated class of `keyboard` actions: `down/up/type/modifiers`

- `Ferrum::Browser#keyboard` - delegated actions to `Ferrum::Keyboard` instance extracted from `Ferrum::Page::Input`

- `Ferrum::Headers` dedicated class of headers manager with `get/set/clear/add` actions which delegated to `Ferrum::Page` instance

- `Ferrum::Cookies` dedicated class which includes logic from `Ferrum::Browser::API::Cookie` & `Ferrum::Cookie` with actions: `all/[]/set/remove/clear`

- `Ferrum::Page#cookies` - delegated actions to `Ferrum::Cookies` instance

- `Ferrum::Page::Screenshot` module with methods `screenshot/pdf` implemented by commands `Page.captureScreenshot/Page.printToPDF`

- `Ferrum::Browser#screenshot` - delegated actions to `Page::Screenshot` module

- `Ferrum::Network::InterceptedRequest` class with methods: `auth_challenge?/match?/abort/continue/url/method/headers/initial_priority/referrer_policy`

- `Ferrum::Browser#intercept_request` - method with delegated to `Ferrum::Page::Net` which sets pattern into `Network.setRequestInterception`

- `Ferrum::Browser#on_request_intercepted` - method with delegated to `Ferrum::Page::Net` which applies passed block

- `Ferrum::Browser#abort_request` - method with delegated to `Ferrum::Page::Net` which stops request by passed interception_id

### Changed

- `Ferrum::Page::Input#send_keys` into `Ferrum::Page::Input#type`

- `Ferrum::DeadBrowser` into `Ferrum::DeadBrowserError`

- `Ferrum::ModalNotFound` into `Ferrum::ModalNotFoundError`

- `Ferrum::StatusFailError` into `Ferrum::StatusError`

- `Ferrum::NodeError` into `Ferrum::NodeNotFoundError`

- `Ferrum::Page#go_back` into `Ferrum::Page#back`

- `Ferrum::Page#go_forward` into `Ferrum::Page#forward`

- `Ferrum::Page::Dom#property` into `Ferrum::Page#property`

- `Ferrum::Page::Dom#select_file` into `Ferrum::Page#select_file`

- `Ferrum::Node::#click` getting the `mode` argument as option with `right/double/left` cases

- `Ferrum::Page::Frame#switch_to_frame` into `Ferrum::Page::Frame#within_frame` with added case of ArgumentError

### Removed

- `Ferrum::ObsoleteNode` error

- `Ferrum::FrameNotFound` error

- `Ferrum::Page::Input#set`

- `Ferrum::Page::Input#select`

- `Ferrum::Node::#attributes`

- `Ferrum::Node::#[]`

- `Ferrum::Node::#select_option`

- `Ferrum::Node::#unselect_option`

- `Ferrum::Node::#visible?`

- `Ferrum::Node::#checked?`

- `Ferrum::Node::#selected?`

- `Ferrum::Node::#disabled?`

- `Ferrum::Node::#path`

- `Ferrum::Node::#right_click`

- `Ferrum::Node::#double_click`

- `Ferrum::Page::Input#type`

- `Ferrum::Page::Input#generate_modifiers`

- `Ferrum::Browser::API` - `Header, Cookie, Screenshot, Intercept`

- `Ferrum::Browser#set_overrides`

- `Ferrum::Browser#url_whitelist`

- `Ferrum::Browser#url_blacklist`

## [0.1.2] - (Aug 27, 2019) ##

### Added

- catch of the intermittent errors inside of `evaluate's` methods

- `Ferrum::Page::Runtime#evaluate_on` - fires `Runtime.callFunctionOn` command with `functionDeclaration` on `Ferrum::Page`

### Removed

- `Ferrum::Page::Runtime#evaluate_in`

## [0.1.1] - (Aug 26, 2019) ##

### Added

- stringify the `url` which passed to `Ferrum::Page#goto`

## [0.1.0] - (Aug 26, 2019) ##

### Added

- fires the `Ferrum::NodeError` on zero of node_id

### Changed

- basic description in README 

## [0.1.0.alpha] - (Aug 2, 2019) ##

### Added

- Initial implementation

    #### Modules:

    - Ferrum

    - Ferrum::Network - simple requests/responses data store

    #### Classes:

    - Ferrum::Browser - basic command interface

    - Ferrum::Cookie - simple store of the cookie attributes

    - Ferrum::Node - abstract level of DOM-node with basic methods

    - Ferrum::Page - basic object of the command references, which included DOM, network and browser logic

    - Ferrum::Targets - initialize of the `window` manager with a clean browser state

    - classes of errors with a description of specific raises reasons

[0.3.0]: https://github.com/rubycdp/ferrum/compare/v0.2.1...v0.3
[0.2.1]: https://github.com/rubycdp/ferrum/compare/v0.2...v0.2.1
[0.2.0]: https://github.com/rubycdp/ferrum/compare/v0.1.2...v0.2
[0.1.2]: https://github.com/rubycdp/ferrum/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/rubycdp/ferrum/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/rubycdp/ferrum/compare/v0.1.0.alpha...v0.1.0
[0.1.0.alpha]: https://github.com/rubycdp/ferrum/releases/tag/v0.1.0.alpha
