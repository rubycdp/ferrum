# frozen_string_literal: true

module Ferrum
  #
  # An opaque reference to a JavaScript value living in the browser, returned
  # by {Frame::Runtime#evaluate_handle}. Unlike {Frame::Runtime#evaluate},
  # which serializes the result into Ruby, a handle keeps the value in the
  # page so it can be passed straight back into a later evaluation without a
  # round trip through JSON.
  #
  # @example
  #   list = page.evaluate_handle("document.querySelectorAll('li')")
  #   page.evaluate("Array.from(nodes).map(n => n.textContent)", nodes: list)
  #
  class RemoteObject
    # @return [String] the CDP remote object id.
    attr_reader :remote_id

    # @return [String] the JavaScript type, e.g. `"object"` or `"function"`.
    attr_reader :type

    # @return [String, nil] the JavaScript subtype, e.g. `"array"` or `"map"`.
    attr_reader :subtype

    # @return [String, nil] the browser's own description of the value.
    attr_reader :description

    #
    # @param [Page] page
    #   The page the value belongs to.
    #
    # @param [Hash] result
    #   A CDP `Runtime.RemoteObject`.
    #
    def initialize(page, result)
      @page = page
      @remote_id = result["objectId"]
      @type = result["type"]
      @subtype = result["subtype"]
      @description = result["description"]
    end

    #
    # Serializes the handle into a plain Ruby value, resolving nodes into
    # {Node} objects the same way {Frame::Runtime#evaluate} does.
    #
    # @return [Object]
    #
    def value
      @page.evaluate("value", value: self)
    end

    #
    # Releases the browser-side reference. The handle is unusable afterwards.
    #
    # @return [void]
    #
    def release
      @page.command("Runtime.releaseObject", objectId: @remote_id)
      nil
    rescue Ferrum::BrowserError
      nil
    end

    # @return [String]
    def inspect
      %(#<#{self.class} @remote_id=#{@remote_id.inspect} @type=#{@type.inspect} ) +
        %(@subtype=#{@subtype.inspect} @description=#{@description.inspect}>)
    end
  end
end
