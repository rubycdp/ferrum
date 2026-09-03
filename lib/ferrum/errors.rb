# frozen_string_literal: true

module Ferrum
  # Base class for all errors raised by Ferrum.
  class Error               < StandardError; end
  # Raised when the referenced page no longer exists.
  class NoSuchPageError     < Error; end
  # Raised when the referenced browser target cannot be found.
  class NoSuchTargetError   < Error; end
  # Raised when a requested feature isn't implemented for the current setup.
  class NotImplementedError < Error; end
  # Raised when no browser binary can be found at the configured path.
  class BinaryNotFoundError < Error; end
  # Raised when a required file path option is empty.
  class EmptyPathError      < Error; end
  # Raised when the browser process server fails to start or crashes.
  class ServerError         < Error; end

  # Raised when a request fails to reach the server, e.g. due to DNS or
  # connectivity issues.
  class StatusError < Error
    def initialize(url, message = nil)
      super(message || "Request to #{url} failed to reach server, check DNS and server status")
    end
  end

  # Raised when the request reached the server, but the page still has
  # pending network connections that never settled.
  class PendingConnectionsError < StatusError
    attr_reader :pendings

    def initialize(url, pendings = [])
      @pendings = pendings
      message = "Request to #{url} reached server, but there are still pending connections"
      message += ": #{pendings.join(', ')}" unless @pendings.empty?

      super(url, message)
    end
  end

  # Raised when waiting for a response from the browser times out.
  class TimeoutError < Error
    # The CDP method that didn't answer in time, `nil` when the wait wasn't for a command.
    #
    # @return [String, nil]
    attr_reader :command

    # The session the command was sent to, `nil` for the browser-wide session.
    #
    # @return [String, nil]
    attr_reader :session_id

    #
    # @param [String, nil] command
    #   The CDP method that timed out.
    #
    # @param [String, nil] session_id
    #   The session it was sent to.
    #
    def initialize(command = nil, session_id: nil)
      @command = command
      @session_id = session_id
      super()
    end

    #
    # Explains that waiting for a response timed out, naming the command when
    # there was one.
    #
    # @return [String]
    #
    def message
      "Timed out waiting for #{awaited}. It's possible that this happened " \
        "because something took a very long time (for example a page load " \
        "was slow). If so, setting the :timeout option to a higher value might " \
        "help. If this happened on an internal protocol call instead, try " \
        "raising :protocol_timeout."
    end

    private

    def awaited
      return "response" unless @command

      @session_id ? "a response to #{@command} (session #{@session_id})" : "a response to #{@command}"
    end
  end

  # Raised when an evaluated script takes too long to return a value.
  class ScriptTimeoutError < Error
    #
    # Explains that the evaluated script timed out.
    #
    # @return [String]
    #
    def message
      "Timed out waiting for evaluated script to return a value"
    end
  end

  # Raised when the browser process doesn't produce a websocket URL within
  # the configured `:process_timeout`.
  class ProcessTimeoutError < Error
    attr_reader :output

    def initialize(timeout, output)
      @output = output
      super("Browser did not produce websocket url within #{timeout} seconds, try to increase `:process_timeout`. See https://github.com/rubycdp/ferrum#customization")
    end
  end

  # Raised when connecting to an already running browser, but its
  # `/json/version` endpoint doesn't answer with the websocket url.
  class NoWebSocketUrlError < Error
    attr_reader :url

    def initialize(url)
      @url = url
      super("Couldn't get a websocket url out of #{url}, `/json/version` there didn't answer with JSON. " \
            "Check the browser is reachable at that url and that any credentials it needs are part of it")
    end
  end

  # Raised when trying to interact with a browser process that has died or
  # a window that has already been closed.
  class DeadBrowserError < Error
    def initialize(message = "Browser is dead or given window is closed")
      super
    end
  end

  # Raised when a node keeps moving between attempts to interact with it,
  # e.g. while trying to click it.
  class NodeMovingError < Error
    def initialize(node, prev, current)
      @node = node
      @prev = prev
      @current = current
      super(message)
    end

    #
    # Explains that the node moved between attempts to interact with it.
    #
    # @return [String]
    #
    def message
      "#{@node.inspect} that you're trying to click is moving, hence " \
        "we cannot. Previously it was at #{@prev.inspect} but now at " \
        "#{@current.inspect}."
    end
  end

  # Raised when the content quads (coordinates) for a node cannot be computed.
  class CoordinatesNotFoundError < Error
    def initialize(message = "Could not compute content quads")
      super
    end
  end

  # Raised when the `:format` option passed to a screenshot call is not one
  # of the supported formats.
  class InvalidScreenshotFormatError < Error
    def initialize(format)
      valid_formats = Page::Screenshot::SUPPORTED_SCREENSHOT_FORMAT.join(" | ")
      super("Invalid value #{format} for option `:format` (#{valid_formats})")
    end
  end

  # Raised when the browser returns an error response over CDP. Wraps the
  # raw response so callers can inspect its code and data.
  class BrowserError < Error
    attr_reader :response

    def initialize(response)
      @response = response
      super(response["message"])
    end

    #
    # Error code from the raw CDP error response.
    #
    # @return [Integer, nil]
    #
    def code
      response["code"]
    end

    #
    # Additional data from the raw CDP error response.
    #
    # @return [Object, nil]
    #
    def data
      response["data"]
    end
  end

  # Raised when the browser reports that a DOM node no longer exists.
  class NodeNotFoundError < BrowserError; end

  # Raised when there's no JavaScript execution context available to run a
  # command against, e.g. because the frame isn't attached.
  class NoExecutionContextError < BrowserError
    def initialize(response = nil)
      super(response || { "message" => "There's no context available" })
    end
  end

  # Raised when JavaScript evaluated in the page throws an exception. Carries
  # the JS exception's class name, message, and stack trace.
  class JavaScriptError < BrowserError
    attr_reader :class_name, :message, :stack_trace

    def initialize(response)
      @class_name, @message = response["exception"]&.values_at("className", "description")
      @message ||= response["text"]
      @stack_trace = response["stackTrace"]
      super(response.merge("message" => @message))
    end
  end
end
