# frozen_string_literal: true

module Ferrum
  class Error               < StandardError; end
  class NoSuchPageError     < Error; end
  class NoSuchTargetError   < Error; end
  class NotImplementedError < Error; end
  class BinaryNotFoundError < Error; end
  class EmptyPathError      < Error; end
  class ServerError         < Error; end

  class StatusError < Error
    def initialize(url, message = nil)
      super(message || "Request to #{url} failed to reach server, check DNS and server status")
    end
  end

  class PendingConnectionsError < StatusError
    attr_reader :pendings

    def initialize(url, pendings = [])
      @pendings = pendings
      message = "Request to #{url} reached server, but there are still pending connections"
      message += ": #{pendings.join(', ')}" unless @pendings.empty?

      super(url, message)
    end
  end

  class TimeoutError < Error
    #
    # Explains that waiting for a response timed out.
    #
    # @return [String]
    #
    def message
      "Timed out waiting for response. It's possible that this happened " \
        "because something took a very long time (for example a page load " \
        "was slow). If so, setting the :timeout option to a higher value might " \
        "help."
    end
  end

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

  class ProcessTimeoutError < Error
    attr_reader :output

    def initialize(timeout, output)
      @output = output
      super("Browser did not produce websocket url within #{timeout} seconds, try to increase `:process_timeout`. See https://github.com/rubycdp/ferrum#customization")
    end
  end

  class DeadBrowserError < Error
    def initialize(message = "Browser is dead or given window is closed")
      super
    end
  end

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

  class CoordinatesNotFoundError < Error
    def initialize(message = "Could not compute content quads")
      super
    end
  end

  class InvalidScreenshotFormatError < Error
    def initialize(format)
      valid_formats = Page::Screenshot::SUPPORTED_SCREENSHOT_FORMAT.join(" | ")
      super("Invalid value #{format} for option `:format` (#{valid_formats})")
    end
  end

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

  class NodeNotFoundError < BrowserError; end

  class NoExecutionContextError < BrowserError
    def initialize(response = nil)
      super(response || { "message" => "There's no context available" })
    end
  end

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
