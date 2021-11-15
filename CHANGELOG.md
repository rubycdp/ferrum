## [Unreleased](https://github.com/rubycdp/ferrum/compare/v0.11...master) ##

### Added

- Alias `Ferrum::Frame#content=` to `Ferrum::Frame#set_content`
- Alias `Ferrum::Node#propery` to `Ferrum::Node#[]`
- Implement `Ferrum::Network#blacklist=` and `Ferrum::Network#whitelist=`
- Alias `Ferrum::Network#blocklist=` to `Ferrum::Network#blacklist=`
- Alias `Ferrum::Network#allowlist=` to `Ferrum::Network#whitelist=`
- Alias `Ferrum::Page#go` to `Ferrum::Page#go_to`
- `Ferrum::Browser#create_page` accepts now `new_context: true` which can create a page in incognito context, and yields
a block with this page, after which the page is closed.
- `Ferrum::Browser` supports new option `:proxy` https://github.com/rubycdp/ferrum#proxy
- `Ferrum::Network::Response#params` attr_reader added
- `Ferrum::Node`
  - `#selected` check selected option
  - `#select` select option
- `Ferrum::JavaScriptError#stack_trace` attr_reader
- Windows support
- Show warning and accept dialog if no handler given

### Changed

- Use `Concurrent::MVar` as `execution_id` in `Ferrum::Frame`
- Min Ruby version is 2.6 and 3.0 is supported
- `Ferrum::Page#bypass_csp` accepts hash as argument `enabled: true` by default
- `Ferrum::Context#has_target?` -> `Ferrum::Context#target?`
- We now start looking for Chrome first instead of Chromium, the order for checking binaries has changed
- Multiple methods are moved into `Utils`:
  - Ferrum.with_attempts -> Ferrum::Utils::Attempt.with_retry
  - Ferrum.started -> Ferrum::Utils::ElapsedTime.start
  - Ferrum.elapsed_time -> Ferrum::Utils::ElapsedTime.elapsed_time
  - Ferrum.monotonic_time -> Ferrum::Utils::ElapsedTime.monotonic_time
  - Ferrum.timeout? -> Ferrum::Utils::ElapsedTime.timeout?
  - Ferrum.windows? -> Ferrum::Utils::Platform.windows?
  - Ferrum.mac? -> Ferrum::Utils::Platform.mac?
  - Ferrum.mri? -> Ferrum::Utils::Platform.mri?

## [0.11](https://github.com/rubycdp/ferrum/compare/v0.10.2...v0.11) - (Mar 11, 2021) ##

### Fixed

- Typo `Ferrum::Page::Screenshot::PAPEP_FORMATS` -> `Ferrum::Page::Screenshot::PAPER_FORMATS`

### Added

- `Ferrum::CoordinatesNotFoundError`
- `Ferrum::Node`
  - `#wait_for_stop_moving` wait for any js or css movements to finish
  - `#moving?` shows if node is moving
  - `#focusable?` if node can have focus
- `Ferrum::Page`
  - `#playback_rate` shows the rate
  - `#playback_rate=` control css animation speed
  - `position` get window position
  - `position=` set window position
- `Ferrum::Browser#evaluate_on_new_document` evaluate js on every new document
- `--no-startup-window` flag to Chrome by default

### Changed

- `Ferrum::NodeIsMovingError` -> `Ferrum::NodeMovingError`
- `Ferrum::Node::MOVING_WAIT` -> `Ferrum::Node::MOVING_WAIT_DELAY`
- `Ferrum::Node::MOVING_ATTEMPTS` -> `Ferrum::Node::MOVING_WAIT_ATTEMPTS`
- `Concurrent::Hash` -> `Concurrent::Map` in contexts


## [0.10.2](https://github.com/rubycdp/ferrum/compare/v0.10.1...v0.10.2) - (Feb 24, 2021) ##

### Fixed

- Set `Ferrum::Page` `@event` when setting up main frame


## [0.10.1](https://github.com/rubycdp/ferrum/compare/v0.10...v0.10.1) - (Feb 24, 2021) ##

### Fixed

- Don't mutate options in `Ferrum::Frame::Runtime#call`


## [0.10](https://github.com/rubycdp/ferrum/compare/v0.9...v0.10) - (Feb 23, 2021) ##

### Fixed

- `execution_id` in Runtime is called with retry
- Main frame is set correct under some circumstances
- `Network.loadingFailed` event is added to catch canceled requests
- `detectCycle` for cyclic JS objects
- Fall back to JS when finding element position with `get_content_quads`
- Temporary user-data-dir is removed after `Ferrum::Browser::Process#stop`

### Added

- Added alias `go_to` for `goto`
- Introduce `Ferrum::Browser` option `:pending_connection_errors`
- You can pass background to screenshot method `browser.screenshot(background_color: Ferrum::RGBA.new(0, 0, 0, 0.0))`
- `Ferrum::StatusError#pendings` attr_reader added
- `Ferrum::ProcessTimeoutError#output` attr_reader added
- `Ferrum::Page#mhtml`

### Changed

- `Ferrum::Browser::Process::PROCESS_TIMEOUT` is 2 -> 10 by default
- `Ferrum::Browser::Network#authorize` now accepts block
- `Ferrum::Page#pdf` method now streams file with `transferMode: "ReturnAsStream"` mode good for large files

### Removed


## [0.9](https://github.com/rubycdp/ferrum/compare/v0.8...v0.9) - (Jul 24, 2020) ##

### Fixed

- `Ferrum::Network::Request#respond` can accept content longer than 45 chars
- `Ferrum::Browser::Subscriber` is thread safe

### Added

- `Ferrum::NodeIsMovingError` to raise error when node is moving before clicking
- `FERRUM_NODE_MOVING_WAIT` and `FERRUM_NODE_MOVING_ATTEMPTS` envs are added to wait until node stops moving with
at least `n` attempts
- `Ferrum::Page#wait_for_reload` waits until page is reloaded
- `:ignore_default_browser_options` option is added to `Ferrum::Browser` to exclude Ferrum's defaults
- XVFB support
- `Ferrum::Runtime::CyclicObject` is returned when JS object cannot be represented in Ruby
- `FERRUM_LOGGING_SCREENSHOTS` env is added to skip showing Base64 screenshots in logger


## [0.8](https://github.com/rubycdp/ferrum/compare/v0.7...v0.8) - (Apr 7, 2020) ##

### Fixed

- `Ferrum::Frame#execution_id` should be set only once
- `Ferrum::Page#doctype` can be nil
- Add `:slowmoable` option to all methods with visual representation
- `Ferrum::Page#screenshot` works for html tag set with 100% width and height

### Added

- `Ferrum::Frame` supports looking up nodes inside frame with methods:
  - `#at_css`
  - `#css`
  - `#at_xpath`
  - `#xpath`
- `Ferrum::Page#set_content` can be used to set the content of the page
- `:ws_max_receive_size` option is added to `Ferrum::Browser`
- `Ferrum::ProcessTimeoutError` error instead of `RuntimeError`
- `Ferrum::Page#stop` to stop loading page

### Changed

- Fix Ruby 2.7 warnings
- `Ferrum::Node#click` accepts `offset: { :x, :y, :position (:top | :center)` and `:delay` options
- Instantiate empty main frame in advance
- `Ferrum::Mouse#move` supports steps as option `:steps`
- Delegate`current_title` to page
- `Ferrum::Browser::Cookies#set` supports `:httponly` and `:samesite` options

### Removed

- `.ruby-version` file from repository


## [0.7](https://github.com/rubycdp/ferrum/compare/v0.6.2...v0.7) - (Jan 28, 2020) ##

### Fixed

- Fix issue when connection is refused and shows up as pending
- Can set `Accept-Language` even if `User-Agent` is not provided

### Added

- `FERRUM_GOTO_WAIT` env is added with default value of 0.1
- `Ferrum::Network::Response#type` shows type of the response
- `Ferrum::Network`
  - `#wait_for_idle` wait for network idle
  - `idle?` shows if there are no connections
  - `total_connections` shows total number of connections
  - `finished_connections` shows a number of closed connections
  - `pending_connections` shows a number of opened connections
- `Ferrum::Network::Exchange`
  - `#intercepted_request` attr accessor for intercepted request if any
  - `#blank?` shows if request is absent
  - `#finished?` returns true if request blocked or response is given
  - `#pending?` shows if exchange is still waiting response
- `Ferrum::Network::InterceptedRequest`
  - `#status?` one of `responded|continued|aborted`
- Initial support for Firefox
- Dedicated queue for request interruptions
- `Ferrum::Browser`
  - accepts `:extensions` option with `:source` key which can have js text to be executed when page is opened
  - `#bypass_csp` can now bypass csp headers when injecting scripts

### Changed

- `Ferrum::StatusError#pendings` now shows all pending connections when time is out
- `Ferrum::Browser::Process#path` is delegated to `Command`

### Removed

- Stop listening to `Page.domContentEventFired`, `Page.frameScheduledNavigation` and
`Page.frameClearedScheduledNavigation` events


## [0.6.2](https://github.com/rubycdp/ferrum/compare/v0.6.1...v0.6.2) - (Oct 30, 2019) ##

### Added

- `Ferrum::Target`:
  - `#page=` attribute writer
  - `#maybe_sleep_if_new_window` - sleep with `Ferrum::Target::NEW_WINDOW_WAIT` seconds by `Ferrum::Target#window?`
  condition


## [0.6.1](https://github.com/rubycdp/ferrum/compare/v0.6...v0.6.1) - (Oct 30, 2019) ##

### Added

- `Ferrum::Frame#execution_id?` - boolean of equals passed argument `execution_id` and current `execution_id` from
current class instance

### Changed

- `Ferrum::Page::Frames` - fix missing frame:
  - `#frame_by` - optional argument `execution_id` removed with change subscriber to search by
  `Ferrum::Frame#execution_id?`


## [0.6.0](https://github.com/rubycdp/ferrum/compare/v0.5...v0.6) - (Oct 29, 2019) ##

### Added

- description of `browser.add_script_tag/browser.add_style_tag` in README
- `Ferrum::Target#attached?` - boolean of the check the exists of `Ferrum::Target#page`
- `Ferrum::Page::Screenshot::DEFAULT_PDF_OPTIONS` - pdf settings constant
- `Ferrum::Page::Screenshot::PAPER_FORMATS` - available formats constant
- `Ferrum::Page::Frames` module implementation:
  - `#main_frame` - attribute reader as new instance of `Ferrum::Frame` created by
  `Runtime.executionContextCreated.context.auxData.frameId`
  - `#frames` - results of delegated `#values` method into instance variable `frames`
  - `#frame_by` - searching method by attributes: id, execution_id, name (optional)
  - `#frames_subscribe` - apply listeners of 'Page/Network/Runtime' streams of the frame-related events
- `Ferrum::Browser#add_script_tag` - delegation to `Ferrum::Page#add_script_tag`
- `Ferrum::Browser#add_style_tag` - delegation to `Ferrum::Page#add_style_tag`
- `Ferrum::Network::AuthRequest` class implementation:
  - initializer accepts two arguments:
  - `page` as first - instance of `Ferrum::Page`
  - `params` as second - params from `on` subscriber "Fetch.authRequired"
  - `#navigation_request?` - delegation to `isNavigationRequest` of passed to instance `params`
  - `#auth_challenge?` - strict equal of `source` as argument with delegation to `authChallenge.source` of
  passed to instance `params`
  - `#match?` - boolean match of `regexp` as argument with `#url`
  - `#continue` - fires the `command` `Fetch.continueWithAuth` on `Ferrum::Page` instance with passed `options`
  as argument
  - `#abort` - fires the `command` `Fetch.failRequest` on `Ferrum::Page` instance with errorReason: "BlockedByClient"
  on current `requestId`
  - `#url` - delegation to `request.url` of passed to instance `params`
  - `#method` - delegation to `request.method` of passed to instance `params`
  - `#headers` - delegation to `request.headers` of passed to instance `params`
  - `#initial_priority` - delegation to `request.initialPriority` of passed to instance `params`
  - `#referrer_policy` - delegation to `request.referrerPolicy` of passed to instance `params`
  - `#inspect` - simple implementation of native `inspect` method with returns of the current internal state

### Changed

- `Ferrum::Page::Screenshot#screenshot` - handle `:full` option
- `Ferrum::Page::Frame` into `Ferrum::Frame`:
  - initializer accepts three arguments:
  - `id` as first - value of `Page.frameAttached.frameId`
  - `page` as second - instance of `Ferrum::Page`
  - `parent_id` as third - with `nil` as default value
  - `Ferrum::Page::Frame#name/Ferrum::Page::Frame#name=` - class attribute accessor
  - `Ferrum::Page::Frame#state=` - attribute writer for `state` instance variable, can be
  `started_loading | navigated | scheduled_navigation | cleared_scheduled_navigation | stopped_loading`
  - `Ferrum::Page::Frame#main?` - boolean of the check the not existed parent_id instance variable
  - `Ferrum::Page::Frame#execution_context_id` converted into `Ferrum::Frame#execution_id` with
  use `execution_id` instance variable
  - `Ferrum::Page::Frame#frame_url` into `Ferrum::Frame#url` - 'document.location.href' reference
  - `Ferrum::Page::Frame#frame_title` into `Ferrum::Frame#title` - 'document.title' reference
  - `Ferrum::Page::Frame#inspect` - simple implementation of native `inspect` method with returns of the current
  internal state
- `Ferrum::Page::DOM` into `Ferrum::Frame::DOM`:
  - `Ferrum::Page::DOM#title` renamed into `Ferrum::Frame::DOM#current_title`
  - `Ferrum::Frame::DOM#doctype` - serialized 'document.doctype' reference
  - `Ferrum::Frame::DOM#css/Ferrum::Frame::DOM#at_css` - added `@page` references for command related methods
- `Ferrum::Page::Runtime` into `Ferrum::Frame::Runtime`:
  - `Ferrum::Frame::DOM#evaluate_on` - added `@page` references for command related methods
  - `Ferrum::Frame::SCRIPT_SRC_TAG` - js implementation for: createElement <script>, fil in `src` with appendChild
  into document.head
  - `Ferrum::Frame::SCRIPT_TEXT_TAG` - js implementation for: createElement <script>, fil in `text` with appendChild
  into document.head
  - `Ferrum::Frame::STYLE_TAG` - js implementation for: createElement <style> with appendChild into document.head
  - `Ferrum::Frame::LINK_TAG` - js implementation for: createElement <link>, fil in `href` with appendChild into
  document.head
  - `Ferrum::Frame::Runtime#add_script_tag` - fires `evaluate_async` with passed args: url, path, content,
  type: "text/javascript"
  - `Ferrum::Frame::Runtime#add_style_tag` - fires `evaluate_async` with passed args: url, path, content
- `Ferrum::Network` - switch from deprecated `Network.continueInterceptedRequest` to `Fetch.continueRequest`
- `Ferrum::Network::Exchange`:
  - first argument `page` for initialize with fill `page` instance variable
  - `#build_response` - fix arguments for `Network::Response.new`
  - `#inspect` - simple implementation of native `inspect` method with returns of the current internal state
- `Ferrum::Network::InterceptedRequest`:
  - `#interception_id` into `#request_id` as `requestId` reference on passed `params`
  - `#respond` - the `custom request fulfilment support` implementation by fires the `command` `Fetch.failRequest`
  on `Ferrum::Page` instance with passed `options` as argument
- `Ferrum::Network::Response`:
  - first argument `page` for initialize with fill `page` instance variable
  - `#body` - implementation of ability to get response body by fires the `command` `Network.getResponseBody`
  on `Ferrum::Page` instance with on specific `requestId`
  - `#main?` - boolean of equals `page.network.response` and current class instance
  - `#==` - boolean of equals passed argument object.id and current `requestId` from `params` instance variable
  - `#inspect` - simple implementation of native `inspect` method with returns of the current internal state
- `Ferrum::Node`:
  - replaced first argument `page` into `frame` / `page` instance variable initialized as `frame.page`
  - `#frame_id` - delegation to `frameId` of passed to instance `description`
  - `#frame` - instance of frame from `page` instance found by `#frame_id`
- `Ferrum::Page::Event` - add frames implementation:
  - `event/document_id` attribute readers
  - `#subscribe` listeners replaced with `#frames_subscribe` from included `Ferrum::Page::Frames` instance
  - `#resize` - evaluate JS: document.documentElement.scrollWidth, document.documentElement.scrollHeight for
  fullscreen case

### Removed

- `Ferrum::Page`
  - `#frame_name`
  - `#frame_url`, with delegated `Ferrum::Browser#frame_url`
  - `#frame_title`, with delegated `Ferrum::Browser#frame_title`
  - `#within_frame`, with delegated `Ferrum::Browser#within_frame`
- `Ferrum::Page::Event`:
  - include DOM, Runtime, Frame
  - `waiting_frames` instance variable
  - `frame_stack` instance variable


## [0.5.0](https://github.com/rubycdp/ferrum/compare/v0.4...v0.5) - (Sep 27, 2019) ##

### Added

- description of `Thread safety` approach section in README
- `Ferrum::NoSuchTargetError`
- `Ferrum::Network::Request#url_fragment` - delegation to `urlFragment` of instance `request`
- The removing of temporary directory on `Ferrum::Browser::Process#stop`: `Ferrum::Browser::Process.directory_remover`
proc for remove entry with the passed path to the temporary directory as an argument
- `Ferrum::Page#viewport_size` - evaluates JS: `innerWidth` and `innerHeight` values on `window` object
- `Ferrum::Page#document_size` - evaluates JS: `offsetWidth` and `offsetHeight` values on `document.documentElement`
object
- `Ferrum::Browser#viewport_size` - delegation to `Ferrum::Page#viewport_size`
- `Ferrum::Context` class implementation:
  - initializer accepts three arguments:
  - `browser` as first - instance of `Ferrum::Browser`
  - `contexts` as second - instance of `Ferrum::Contexts`
  - `id` as third - the value of browser command: `Target.createBrowserContext.browserContextId`
  - includes `id` attribute reader - the passed argument: `id`
  - includes `targets` attribute reader - the thread safe instance of hash
  - includes `pendings` attribute reader - the thread safe instance of mutable variable
  - includes `POSITION` constant - the freeze array of `first` `last` symbols
  - `#default_target` - memoization of `#create_target` result
  - `#create_target` - assigns `target.id` as fetch of `targetId` from `Target.createTarget` with assign `target`
  from `targetInfo`
  - `#page` - delegation to `default_target` of `Ferrum::Context`
  - `#pages` - delegations to `page`'s taken from `Ferrum::Context#targets` as `values`
  - `#windows` - delegations to `page`'s taken from `Ferrum::Context#targets` as `values` with `window?` truthy
  condition takes `position` as first argument and optional second argument `size` with `1` as default value may raise
  `ArgumentError` on the passed `position` which not included into `Ferrum::Context::POSITION` constant values
  - `#create_page` - delegation to `target` with the `target` recreation by `Ferrum::Context#create_target`
  - `#add_target` - creates new instance of `Ferrum::Target` with fill by `Ferrum::Target.window?` condition of:
  `targets` instance variable on `id` or `pendings` instance variable as replace of `@value`
  - `#update_target` - updates specific `target` in `targets` instance variable by `target_id` and `params` which are
  passed as arguments
  - `#delete_target` - deletes from `targets` instance variable by passed `target_id` as argument
  - `#dispose` - disposes from `contexts` instance variable by passed `id` as attribute reader
  - `#inspect` - simple implementation of native `inspect` method with returns of the current internal state
- `Ferrum::Target` class implementation:
  - initializer accepts two arguments:
  - `browser` as first - instance of `Ferrum::Browser`
  - `params` as second (optional) - instance of `Ferrum::Contexts`
  - `#update` - attribute writer for `params` instance variable by passed `params` as one argument
  - `#page` - new instance of `Ferrum::Page` created for specific `targetId`
  - `#window?` - boolean of the check the exists of `Ferrum::Target#opener_id`
  - `#id` - delegation to `targetId` of passed to instance `params`
  - `#type` - delegation to `type` of passed to instance `params`
  - `#title` - delegation to `title` of passed to instance `params`
  - `#url` - delegation to `url` of passed to instance `params`
  - `#opener_id` - delegation to `openerId` of passed to instance `params`
  - `#context_id` - delegation to `browserContextId` of passed to instance `params`
- `Ferrum::Contexts` class implementation: (subscriber on `Target.targetCreated`)
  - initializer accepts `browser` as the one argument
  - includes `contexts` attribute reader - the thread safe instance of hash
  - `#default_context` - memoization of `#create` result
  - `#find_by` - finding the last match in `contexts` instance variable by match of passed `target_id`
  into `targets.keys` required `target_id: value` argument  returns `nil` on the not-matched case
  - `#create` - assigns new instance of `Ferrum::Context` with fetched `browserContextId` from
  `Target.createBrowserContext` into `contexts` instance variable returns the created instance of `Ferrum::Context`
  - `#dispose` - removes specific `context` from `contexts` instance variable by passed `context_id` with fires
  `Target.disposeBrowserContext` browser command returns `true` boolean on the success dispose
  - `#reset` - nullify the `default_context` instance variable and fires the `dispose` method on each `context` in
  `contexts` instance variable
- `Ferrum::Browser#contexts` - reader of `Ferrum::Contexts` instance:
- `Ferrum::Browser#default_context` - delegation to `Ferrum::Browser#contexts`
- the delegation to `Ferrum::Browser#default_context`:
  - `Ferrum::Browser#create_target`
  - `Ferrum::Browser#create_page`
  - `Ferrum::Browser#pages`
  - `Ferrum::Browser#windows`

### Changed

- `Ferrum::NoSuchWindowError` into `NoSuchPageError`
- `Ferrum::Page::NEW_WINDOW_WAIT` moved as unchanged to `Ferrum::Target`
- `Ferrum::Browser#page` - the delegation from `Ferrum::Browser#targets` to `Ferrum::Browser#default_context`
- `Ferrum::Browser#page` - from the instance of `Ferrum::Browser#targets` into delegation
to `Ferrum::Browser#default_context`

### Removed

- `Ferrum::EmptyTargetsError`
- the `hack` to handle `new window` which doesn't have events at all by `Ferrum::Page#session_id` with
`Target.attachToTarget` and `Target.detachFromTarget` usage
- `Ferrum::Page#close_connection` - the logic is moved to `Ferrum::Page#close` directly
- the third argument (`new_window = false`) for `Ferrum::Page` initializer
- `Ferrum::Targets` class with the delegations to `Ferrum::Targets` instance in `Ferrum::Browser` instance:
  - `Ferrum::Browser#window_handle`
  - `Ferrum::Browser#window_handles`
  - `Ferrum::Browser#switch_to_window`
  - `Ferrum::Browser#open_new_window`
  - `Ferrum::Browser#close_window`
  - `Ferrum::Browser#within_window`


## [0.4.0](https://github.com/rubycdp/ferrum/compare/v0.3...v0.4) - (Sep 17, 2019) ##

### Added

- `Ferrum::Network` module - moved logic from `Ferrum::Page::Net` with addition changes
- `Ferrum::Browser#network` - instance of `Ferrum::Network` from delegated `Ferrum::Page` instance
- `Ferrum::Network#request` & `Ferrum::Network#response` - delegation to `Network::Exchange` instance
- `Ferrum::Network#first_by` / `Ferrum::Network#last_by` - implemented searching by passed request_id in
`Network::Exchange` instance
- `Ferrum::Browser#traffic` delegation to `Ferrum::Network` of `Network::Exchange` instances
- `Ferrum::Network::Exchange` - simple request/response constructor with monitoring
  - `#build_request` - instance of `Network::Request` with passed params
  - `#build_response` - instance of `Network::Response` with passed params
  - `#build_error` - instance of `Network::Error` with passed params
  - `#navigation_request?` - the request verification on document by passed frame_id
  - `#blocked?` - boolean which becomes true when no the constructed response
  - `#to_a` - returns array of constructed request/response/error instances
- `Ferrum::Network::Request#type` - delegation to `type` of passed to instance params
- `Ferrum::Network::Request#type?` - boolean compare with `type` of instance with passed type as argument
- `Ferrum::Network::Request#frame_id` - delegation to `frameId` of passed to instance params
- `Ferrum::Network::InterceptedRequest#abort` - fires `continue` method of instance with `errorReason` as `Aborted`
- `Ferrum::Network::InterceptedRequest#inspect` - simple implementation of native `inspect` method with returns of the
current internal state
- `Ferrum::Page::Frame#frame_id` - reader to public available of `frameId` by `Ferrum::Page#frame_id`

### Changed

- description of `Network/Authorization/Interception` sections in README
- `Ferrum::Browser#screenshot` & `Ferrum::Browser#pdf` methods are returns bin when no path is given
- `Ferrum::Browser#status` delegated to `Ferrum::Network`
- `Ferrum::Browser#authorize` delegated to `Ferrum::Network`
- `Ferrum::Network` module into `class` approach for `InterceptedRequest/Request/Response/Error` classes
- `Ferrum::Browser#intercept_request` into `Ferrum::Network#intercept`
- `Ferrum::Browser#subscribe` into `Ferrum::Network#subscribe` with public available
- `Ferrum::Browser#authorized_response` into `Ferrum::Network#authorized_response` with public available
- `Ferrum::Browser#clear_memory_cache` & `Ferrum::Browser#clear_network_traffic` merged to `Ferrum::Network#clear`
with addition of `traffic` clear by the argument as symbol type of `traffic/cache`
- `Ferrum::Network::Request#time` - use `wallTime` params fir time detection
- `body_size` attribute writer of `Ferrum::Network::Response` with reduce of size on headers_size
to handle `encodedDataLength` when `Network.responseReceived` is not dispatched

### Removed

- `Ferrum::Network::Response#redirect_url`
- `Ferrum::Page::Net`
- `Ferrum::Browser#abort_request`
- `Ferrum::Browser#continue_request`
- `Ferrum::Browser#response_headers`
- `Ferrum::Browser#network_traffic`
- `Ferrum::Network::InterceptedRequest#is_navigation_request=` (attribute writer)


## [0.3.0](https://github.com/rubycdp/ferrum/compare/v0.2.1...v0.3) - (Sep 12, 2019) ##

### Added

- CI build by TravisCI for ruby versions: `2.3/2.4/2.5/2.6/jruby-9.2.8.0`
- fix specs with support of MacOS time formats
- `Ferrum::Mouse::CLICK_WAIT` as `FERRUM_CLICK_WAIT` `ENV-var` with `0.1` as default value
- `Ferrum::Browser#authorize` option `:type` with valid values `:server` (by default), `:proxy`
- Logo :tada:
- `Ferrum::Node#inner_text` - evaluates JS: `this.innerText` on Node instance
- `Ferrum::Page::Runtime::INTERMITTENT_ATTEMPTS` as `FERRUM_INTERMITTENT_ATTEMPTS` `ENV-var` with `6` as default value
- `Ferrum::Page::Runtime::INTERMITTENT_SLEEP` as `FERRUM_INTERMITTENT_SLEEP` `ENV-var` with `0.1` as default value
- `Ferrum::Page#on` getting the `name` as option with `:dialog/:request_intercepted` cases & `block` as last argument
- `Ferrum::Browser#on` - delegated actions to `Ferrum::Page` instance
- `Ferrum::Dialog` object to handle JavaScript Dialog's
  - required `page, params` as init arguments
  - `#accept` fires JS: `Page.handleJavaScriptDialog` as command on provided `Ferrum::Page` instance with options
  which included `accept: true`
  - `#dismiss` fires JS: `Page.handleJavaScriptDialog` as command on provided `Ferrum::Page` instance
  with `accept: false`
  - `#match?` compare message by passed regexp
  - description of `Dialog` feature in README
- `Ferrum::Page::Event` extend of `Concurrent::Event` with implementation of `reset/wait` fix
  - implement `Ferrum::Page::Event#iteration` to reuse `synchronize` block on `@iteration` value of `Concurrent::Event`
  - redefinition of `Concurrent::Event#reset` - increase `@iteration` outside of `if @set` block
- `FERRUM_PROCESS_TIMEOUT` `ENV-var` as `Ferrum::Browser::Process::PROCESS_TIMEOUT` with `2` as default value
- Elapsed time implementation:
  - `Ferrum::Browser::Process::WAIT_KILLED` with `0.05`
  - `Ferrum.monotonic_time` - delegation to `Concurrent` object
  - `Ferrum.started` - class variable `@@started` as `monotonic_time`
  - `Ferrum.elapsed_time` - a difference of `monotonic_time` as minuend and passed time as argument or `@@started`
  as subtrahend
  - `Ferrum.timeout?` - boolean compare passed values `(start, timeout)` by `elapsed_time`
- JRuby support by replaces of `::Process::CLOCK_MONOTONIC` usages according to `Elapsed-time` implementation

### Changed

- fix globally changing of Thread behaviour on options `abort_on_exception/report_on_exception`
- `Ferrum::Page::Input#find_position` into `Ferrum::Node#find_position`
- `Ferrum::Browser#scroll_to` into `Ferrum::Mouse#scroll_to`
- option `:timeout` into `:wait` for `Ferrum::Page#command` / `Ferrum::Mouse#click`
- description of `Authorization` options in README
- `Ferrum::Page::Net#intercept_request` block as last argument into `Ferrum::Page::Net#on(:request_intercepted)`
with passed block
- `Ferrum::Browser::TIMEOUT` into `Ferrum::Browser::DEFAULT_TIMEOUT` as `FERRUM_DEFAULT_TIMEOUT` `ENV-var` with `5`
as default value
- usage of `Concurrent::Event` into `Ferrum::Page::Event` as `@event` of `Ferrum::Page` instance
- `Ferrum::Page::NEW_WINDOW_BUG_SLEEP` into `Ferrum::Page::NEW_WINDOW_WAIT` as `FERRUM_NEW_WINDOW_WAIT` `ENV-var`
with `0.3` as default value

### Removed

- `Ferrum::Page::Input`
- `Ferrum::Browser#proxy_authorize` / `Ferrum::Page::Net#proxy_authorize`
- `Ferrum::ModalNotFoundError`
- `Ferrum::Page#reset_modals` with delegation to `Ferrum::Browser`
- `Ferrum::Page#find_modal` with delegation to `Ferrum::Browser`
- `Ferrum::Page#accept_prompt` with delegation to `Ferrum::Browser`
- `Ferrum::Page#dismiss_confirm` with delegation to `Ferrum::Browser`
- `Ferrum::Page#accept_confirm` with delegation to `Ferrum::Browser`
- `Ferrum::Browser#on_request_intercepted`


## [0.2.1](https://github.com/rubycdp/ferrum/compare/v0.2...v0.2.1) - (Sep 5, 2019) ##

### Added

- handle `EOFError/Errno::ECONNRESET/Errno::EPIPE` errors with rescue
- description options of `Customization` in README

### Changed

- increased `Browser::Process::PROCESS_TIMEOUT` constant by 1
- `Ferrum::Network::InterceptedRequest#match?` to handle cases for `Ruby 2.3` and less


## [0.2.0](https://github.com/rubycdp/ferrum/compare/v0.1.2...v0.2) - (Sep 3, 2019) ##

### Added

- snippet examples of the actions in README
- `Ferrum::Node#focus` - fires the `command` `DOM.focus` on `Ferrum::Page` instance
- `Ferrum::Node#blur` - evaluates JS: `this.blur()` on `Ferrum::Page` instance
- `Ferrum::Node#click` - fires the native `click` on `Ferrum::Page` instance
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
- `Ferrum::Headers` dedicated class of headers manager with `get/set/clear/add` actions which delegated to
`Ferrum::Page` instance
- `Ferrum::Cookies` dedicated class which includes logic from `Ferrum::Browser::API::Cookie` & `Ferrum::Cookie`
with actions: `all/[]/set/remove/clear`
- `Ferrum::Page#cookies` - delegated actions to `Ferrum::Cookies` instance
- `Ferrum::Page::Screenshot` module with methods `screenshot/pdf` implemented by
commands `Page.captureScreenshot/Page.printToPDF`
- `Ferrum::Browser#screenshot` - delegated actions to `Page::Screenshot` module
- `Ferrum::Network::InterceptedRequest`
  - `auth_challenge?`
  - `match?`
  - `abort`
  - `continue`
  - `url`
  - `method`
  - `headers`
  - `initial_priority`
  - `referrer_policy`
- `Ferrum::Browser#intercept_request` - method with delegated to `Ferrum::Page::Net` which sets pattern
into `Network.setRequestInterception`
- `Ferrum::Browser#on_request_intercepted` - method with delegated to `Ferrum::Page::Net` which applies passed block
- `Ferrum::Browser#abort_request` - method with delegated to `Ferrum::Page::Net` which stops request
by passed interception_id

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
- `Ferrum::Page::Frame#switch_to_frame` into `Ferrum::Page::Frame#within_frame` with added case of `ArgumentError`

### Removed

- `Ferrum::ObsoleteNode` error
- `Ferrum::FrameNotFound` error
- `Ferrum::Page::Input#set`
  - `#set`
  - `#select`
  - `#type`
  - `#generate_modifiers`
- `Ferrum::Node`
  - `#attributes`
  - `#[]`
  - `#select_option`
  - `#unselect_option`
  - `#visible?`
  - `#checked?`
  - `#selected?`
  - `#disabled?`
  - `#path`
  - `#right_click`
  - `#double_click`
- `Ferrum::Browser::API` - `Header, Cookie, Screenshot, Intercept`
- `Ferrum::Browser`
  - `#set_overrides`
  - `#url_whitelist`
  - `#url_blacklist`


## [0.1.2](https://github.com/rubycdp/ferrum/compare/v0.1.1...v0.1.2) - (Aug 27, 2019) ##

### Added

- catch of the intermittent errors inside of `evaluate's` methods
- `Ferrum::Page::Runtime#evaluate_on` - fires `Runtime.callFunctionOn` command
with `functionDeclaration` on `Ferrum::Page`

### Removed

- `Ferrum::Page::Runtime#evaluate_in`


## [0.1.1](https://github.com/rubycdp/ferrum/compare/v0.1.0...v0.1.1) - (Aug 26, 2019) ##

### Added

- stringify the `url` which passed to `Ferrum::Page#goto`


## [0.1.0](https://github.com/rubycdp/ferrum/compare/v0.1.0.alpha...v0.1.0) - (Aug 26, 2019) ##

### Added

- fires the `Ferrum::NodeError` on zero of `node_id`

### Changed

- basic description in README


## [0.1.0.alpha](https://github.com/rubycdp/ferrum/releases/tag/v0.1.0.alpha) - (Aug 2, 2019) ##

### Added

- Initial implementation
  - `Ferrum`
  - `Ferrum::Network` - simple requests/responses data store
  - `Ferrum::Browser` - basic command interface
  - `Ferrum::Cookie` - simple store of the cookie attributes
  - `Ferrum::Node` - abstract level of DOM-node with basic methods
  - `Ferrum::Page` - basic object of the command references, which included `DOM`, network and browser logic
  - `Ferrum::Targets` - initialize of the `window` manager with a clean browser state
  - classes of errors with a description of specific reason
