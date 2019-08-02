# frozen_string_literal: true

Thread.abort_on_exception = true
Thread.report_on_exception = true if Thread.respond_to?(:report_on_exception=)

module Ferrum
  require "ferrum/browser"
  require "ferrum/node"
  require "ferrum/errors"
  require "ferrum/cookie"

  class << self
    def windows?
      RbConfig::CONFIG["host_os"] =~ /mingw|mswin|cygwin/
    end

    def mac?
      RbConfig::CONFIG["host_os"] =~ /darwin/
    end

    def mri?
      defined?(RUBY_ENGINE) && RUBY_ENGINE == "ruby"
    end
  end
end
