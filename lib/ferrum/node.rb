# frozen_string_literal: true

module Ferrum
  class Node
    attr_reader :page, :target_id, :node_id, :description, :tag_name

    def initialize(page, target_id, node_id, description)
      @page, @target_id = page, target_id
      @node_id, @description = node_id, description
      @tag_name = description["nodeName"].downcase
    end

    def node?
      description["nodeType"] == 1 # nodeType: 3, nodeName: "#text" e.g.
    end

    def focus
      tap { page.command("DOM.focus", nodeId: node_id) }
    end

    def blur
      tap { evaluate("this.blur()") }
    end

    def type(*keys)
      tap { page.type(self, keys) }
    end

    def click(keys = [], offset = {})
      tap { page.click(self, keys, offset) }
    end

    def right_click(keys = [], offset = {})
      tap { page.right_click(self, keys, offset) }
    end

    def double_click(keys = [], offset = {})
      tap { page.double_click(self, keys, offset) }
    end

    def hover
      tap { page.hover(self) }
    end

    def trigger(event)
      tap { page.trigger(self, event) }
    end

    def select_file(value)
      page.command("DOM.setFileInputFiles", nodeId: node_id, files: Array(value))
    end

    def at_xpath(selector)
      page.at_xpath(selector, within: self)
    end

    def at_css(selector)
      page.at_css(selector, within: self)
    end

    def xpath(selector)
      page.xpath(selector, within: self)
    end

    def css(selector)
      page.css(selector, within: self)
    end

    def text
      evaluate("this.textContent")
    end

    def value
      evaluate("this.value")
    end

    def property(name)
      evaluate("this['#{name}']")
    end

    def attribute(name)
      evaluate("this.getAttribute('#{name}')")
    end

    def evaluate(expression)
      page.evaluate_on(node: self, expression: expression)
    end

    def ==(other)
      return false unless other.is_a?(Node)
      # We compare backendNodeId because once nodeId is sent to frontend backend
      # never returns same nodeId sending 0. In other words frontend is
      # responsible for keeping track of node ids.
      target_id == other.target_id && description["backendNodeId"] == other.description["backendNodeId"]
    end

    def inspect
      %(#<#{self.class} @target_id=#{@target_id.inspect} @node_id=#{@node_id} @description=#{@description.inspect}>)
    end
  end
end
