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
      tap { page.keyboard.type(*keys) }
    end

    # mode: (:left | :right | :double)
    # keys: (:alt, (:ctrl | :control), (:meta | :command), :shift)
    # offset: { :x, :y }
    def click(mode: :left, keys: [], offset: {})
      x, y = find_position(offset[:x], offset[:y])
      modifiers = page.keyboard.modifiers(keys)

      case mode
      when :right
        page.mouse.move(x: x, y: y)
        page.mouse.down(button: :right, modifiers: modifiers)
        page.mouse.up(button: :right, modifiers: modifiers)
      when :double
        page.mouse.move(x: x, y: y)
        page.mouse.down(modifiers: modifiers, count: 2)
        page.mouse.up(modifiers: modifiers, count: 2)
      when :left
        page.mouse.click(x: x, y: y, modifiers: modifiers)
      end

      self
    end

    def hover
      raise NotImplementedError
    end

    def trigger(event)
      raise NotImplementedError
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

    def find_position(offset_x = nil, offset_y = nil)
      quads = get_content_quads
      offset_x, offset_y = offset_x.to_i, offset_y.to_i

      if offset_x > 0 || offset_y > 0
        point = quads.first
        [point[:x] + offset_x, point[:y] + offset_y]
      else
        x, y = quads.inject([0, 0]) do |memo, point|
          [memo[0] + point[:x],
           memo[1] + point[:y]]
        end
        [x / 4, y / 4]
      end
    end

    private

    def get_content_quads
      result = page.command("DOM.getContentQuads", nodeId: node_id)
      raise "Node is either not visible or not an HTMLElement" if result["quads"].size == 0

      # FIXME: Case when a few quads returned
      result["quads"].map do |quad|
        [{x: quad[0], y: quad[1]},
         {x: quad[2], y: quad[3]},
         {x: quad[4], y: quad[5]},
         {x: quad[6], y: quad[7]}]
      end.first
    end
  end
end
