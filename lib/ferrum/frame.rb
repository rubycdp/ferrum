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

    attr_accessor :id, :name
    attr_reader :page, :parent_id, :state

    def initialize(id, page, parent_id = nil)
      @id = id
      @page = page
      @execution_id = nil
      @parent_id = parent_id
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

    def set_content(html)
      evaluate_async(%(
        document.open();
        document.write(arguments[0]);
        document.close();
        arguments[1](true);
      ), @page.timeout, html)
    end

    def execution_id?(execution_id)
      @execution_id == execution_id
    end

    def execution_id
      raise NoExecutionContextError unless @execution_id

      @execution_id
    rescue NoExecutionContextError
      @page.event.reset
      @page.event.wait(@page.timeout) ? retry : raise
    end

    def set_execution_id(value)
      @execution_id ||= value
    end

    def reset_execution_id
      @execution_id = nil
    end

    def inspect
      %(#<#{self.class} @id=#{@id.inspect} @parent_id=#{@parent_id.inspect} @name=#{@name.inspect} @state=#{@state.inspect} @execution_id=#{@execution_id.inspect}>)
    end
  end
end
