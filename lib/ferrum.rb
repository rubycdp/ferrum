# frozen_string_literal: true

require "ferrum/browser"
require "ferrum/node"

module Ferrum
  class Error               < StandardError; end
  class NoSuchPageError     < Error; end
  class NoSuchTargetError   < Error; end
  class NotImplementedError < Error; end

  class StatusError < Error
    def initialize(url, pendings = [])
      message = if pendings.empty?
                  "Request to #{url} failed to reach server, check DNS and/or server status"
                else
                  "Request to #{url} reached server, but there are still pending connections: #{pendings.join(', ')}"
                end

      super(message)
    end
  end

  class TimeoutError < Error
    def message
      "Timed out waiting for response. It's possible that this happened " \
      "because something took a very long time (for example a page load " \
      "was slow). If so, setting the :timeout option to a higher value might " \
      "help."
    end
  end

  class ScriptTimeoutError < Error
    def message
      "Timed out waiting for evaluated script to return a value"
    end
  end

  class ProcessTimeoutError < Error
    attr_reader :output

    def initialize(timeout, output)
      @output = output
      super("Browser did not produce websocket url within #{timeout} seconds")
    end
  end

  class DeadBrowserError < Error
    def initialize(message = "Browser is dead or given window is closed")
      super
    end
  end

  class NodeIsMovingError < Error
    def initialize(node, prev, current)
      @node, @prev, @current = node, prev, current
      super(message)
    end

    def message
      "#{@node.inspect} that you're trying to click is moving, hence " \
      "we cannot. Previosuly it was at #{@prev.inspect} but now at " \
      "#{@current.inspect}."
    end
  end

  class BrowserError < Error
    attr_reader :response

    def initialize(response)
      @response = response
      super(response["message"])
    end

    def code
      response["code"]
    end

    def data
      response["data"]
    end
  end

  class NodeNotFoundError < BrowserError; end

  class NoExecutionContextError < BrowserError
    def initialize(response = nil)
      response ||= { "message" => "There's no context available" }
      super(response)
    end
  end

  class JavaScriptError < BrowserError
    attr_reader :class_name, :message

    def initialize(response)
      @class_name, @message = response.values_at("className", "description")
      super(response.merge("message" => @message))
    end
  end

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

    def started
      @@started ||= monotonic_time
    end

    def elapsed_time(start = nil)
      monotonic_time - (start || @@started)
    end

    def monotonic_time
      Concurrent.monotonic_time
    end

    def timeout?(start, timeout)
      elapsed_time(start) > timeout
    end

    def with_attempts(errors:, max:, wait:)
      attempts ||= 1
      yield
    rescue *Array(errors)
      raise if attempts >= max
      attempts += 1
      sleep(wait)
      retry
    end
  end
end
