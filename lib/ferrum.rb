# frozen_string_literal: true

require "concurrent-ruby"
require "ferrum/utils/event"
require "ferrum/utils/thread"
require "ferrum/utils/platform"
require "ferrum/utils/elapsed_time"
require "ferrum/utils/attempt"
require "ferrum/utils/deprecate"
require "ferrum/errors"
require "ferrum/browser"
require "ferrum/remote_object"
require "ferrum/node"

#
# Ferrum is a pure Ruby driver for headless Chrome and Firefox. It talks
# directly to the browser over the Chrome DevTools Protocol (CDP), so it
# doesn't depend on Selenium, WebDriver or any other third party gem.
#
# {Ferrum::Browser} is the entry point most applications start from.
#
module Ferrum
end
