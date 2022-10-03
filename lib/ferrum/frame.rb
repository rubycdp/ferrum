# frozen_string_literal: true

require "ferrum/frame/dom"
require "ferrum/frame/runtime"

module Ferrum
  class Frame
    include DOM
    include Runtime

    STATE_VALUES = %i[
      started_loading
      navigated
      stopped_loading
    ].freeze

    # The Frame's unique id.
    #
    # @return [String]
    attr_accessor :id

    # If frame was given a name it should be here.
    #
    # @return [String, nil]
    attr_accessor :name

    # The page the frame belongs to.
    #
    # @return [Page]
    attr_reader :page

    # Parent frame id if this one is nested in another one.
    #
    # @return [String, nil]
    attr_reader :parent_id

    # One of the states frame's in.
    #
    # @return [:started_loading, :navigated, :stopped_loading, nil]
    attr_reader :state

    def initialize(id, page, parent_id = nil)
      @id = id
      @page = page
      @parent_id = parent_id
      @execution_id = Concurrent::MVar.new
    end

    def state=(value)
      raise ArgumentError unless STATE_VALUES.include?(value)

      @state = value
    end

    def url
      evaluate("document.location.href")
    end

    def title
      evaluate("document.title")
    end

    def main?
      @parent_id.nil?
    end

    def content=(html)
      evaluate_async(%(
        document.open();
        document.write(arguments[0]);
        document.close();
        arguments[1](true);
      ), @page.timeout, html)
    end
    alias set_content content=

    def execution_id
      value = @execution_id.borrow(@page.timeout, &:itself)
      raise NoExecutionContextError if value.instance_of?(Object)

      value
    end

    def execution_id=(value)
      if value.nil?
        @execution_id.try_take!
      else
        @execution_id.try_put!(value)
      end
    end

    def inspect
      "#<#{self.class} " \
        "@id=#{@id.inspect} " \
        "@parent_id=#{@parent_id.inspect} " \
        "@name=#{@name.inspect} " \
        "@state=#{@state.inspect} " \
        "@execution_id=#{@execution_id.inspect}>"
    end
  end
end
