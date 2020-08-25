# frozen_string_literal: true

require_relative "frame/dom"
require_relative "frame/runtime"

module Ferrum
  class Frame
    include DOM
    include Runtime

    attr_reader :page, :parent_id
    attr_writer :execution_id
    attr_accessor :id, :name, :state

    def initialize(id, page, parent_id = nil)
      @id = id
      @page = page
      @parent_id = parent_id
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

    def reset_execution_id
      @execution_id = nil
    end

    def inspect
      <<~OUTPUT
        #<#{self.class} @id=#{@id.inspect} @parent_id=#{@parent_id.inspect} @name=#{@name.inspect} @state=#{@state.inspect} @execution_id=#{@execution_id.inspect}>
      OUTPUT
    end
  end
end
