# frozen_string_literal: true

module Ferrum
  class NotImplemented < StandardError; end
  class ModalNotFound < StandardError; end
  class Error < StandardError; end
  class NoSuchWindowError < Error; end
  class EmptyTargetsError < Error; end
  class NoExecutionContext < Error; end

  class ClientError < Error
    attr_reader :response

    def initialize(response)
      @response = response
      super(response["message"])
    end
  end

  class BrowserError < ClientError
    def code
      response["code"]
    end

    def data
      response["data"]
    end
  end

  class JavaScriptError < ClientError
    attr_reader :class_name, :message

    def initialize(response)
      super
      @class_name, @message = response.values_at("className", "description")
    end
  end

  class StatusFailError < ClientError
    def message
      "Request to #{response["url"]} failed to reach server, check DNS and/or server status"
    end
  end

  class FrameNotFound < ClientError
    def name
      response["args"].first
    end

    def message
      "The frame \"#{name}\" was not found."
    end
  end

  class NodeError < ClientError
    attr_reader :node

    def initialize(node, response)
      @node = node
      super(response)
    end
  end

  class ObsoleteNode < NodeError
    def message
      "The element you are trying to interact with is either not part of the DOM, or is " \
      "not currently visible on the page (perhaps display: none is set). " \
      "It is possible the element has been replaced by another element and you meant to interact with " \
      "the new element. If so you need to do a new find in order to get a reference to the " \
      "new element."
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

  class DeadBrowser < Error
    def initialize(message = "Browser is dead")
      super
    end
  end
end
