# frozen_string_literal: true

require "ferrum/frame/dom"
require "ferrum/frame/runtime"

module Ferrum
  class Frame
    include DOM, Runtime

    attr_reader :id, :parent_id, :page, :state, :name
    attr_writer :execution_id

    def initialize(page, id, parent_id = nil)
      @page, @id, @parent_id = page, id, parent_id
    end

    # Can be one of:
    # * started_loading
    # * navigated
    # * scheduled_navigation
    # * cleared_scheduled_navigation
    # * stopped_loading
    def state=(value)
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

    def execution_id
      raise NoExecutionContextError unless @execution_id
      @execution_id
    rescue NoExecutionContextError
      @page.event.reset
      @page.event.wait(@page.timeout) ? retry : raise
    end
  end
end
