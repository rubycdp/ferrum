# frozen_string_literal: true

require "ferrum/browser/api/cookie"
require "ferrum/browser/api/header"
require "ferrum/browser/api/screenshot"
require "ferrum/browser/api/intercept"

module Ferrum
  class Browser
    module API
      include Cookie, Header, Screenshot, Intercept
    end
  end
end
