# frozen_string_literal: true

module Ferrum
  class Node
    MOVING_WAIT = ENV.fetch("FERRUM_NODE_MOVING_WAIT", 0.05).to_f
    MOVING_ATTEMPTS = ENV.fetch("FERRUM_NODE_MOVING_ATTEMPTS", 5).to_f

    attr_reader :page, :target_id, :node_id, :description, :tag_name

    def initialize(frame, target_id, node_id, description)
      @page = frame.page
      @target_id = target_id
      @node_id, @description = node_id, description
      @tag_name = description["nodeName"].downcase
    end

    def node?
      description["nodeType"] == 1 # nodeType: 3, nodeName: "#text" e.g.
    end

    def frame_id
      description["frameId"]
    end

    def frame
      page.frame_by(id: frame_id)
    end

    def focus
      tap { page.command("DOM.focus", slowmoable: true, nodeId: node_id) }
    end

    def blur
      tap { evaluate("this.blur()") }
    end

    def type(*keys)
      tap { page.keyboard.type(*keys) }
    end

    # mode: (:left | :right | :double)
    # keys: (:alt, (:ctrl | :control), (:meta | :command), :shift)
    # offset: { :x, :y, :position (:top | :center) }
    def click(mode: :left, keys: [], offset: {}, delay: 0)
      x, y = find_position(**offset)
      modifiers = page.keyboard.modifiers(keys)

      case mode
      when :right
        page.mouse.move(x: x, y: y)
        page.mouse.down(button: :right, modifiers: modifiers)
        sleep(delay)
        page.mouse.up(button: :right, modifiers: modifiers)
      when :double
        page.mouse.move(x: x, y: y)
        page.mouse.down(modifiers: modifiers, count: 2)
        page.mouse.up(modifiers: modifiers, count: 2)
      when :left
        page.mouse.click(x: x, y: y, modifiers: modifiers, delay: delay)
      end

      self
    end

    def hover
      raise NotImplementedError
    end

    def select_file(value)
      page.command("DOM.setFileInputFiles", slowmoable: true, nodeId: node_id, files: Array(value))
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

    # FIXME: clear API for text and inner_text
    def inner_text
      evaluate("this.innerText")
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

    def find_position(x: nil, y: nil, position: :top)
      offset_x, offset_y = x, y
      quads = get_node_quads
      x = y = nil

      if offset_x && offset_y && position == :top
        point = quads.first
        x = point[:x] + offset_x.to_i
        y = point[:y] + offset_y.to_i
      else
        x, y = quads.inject([0, 0]) do |memo, point|
          [memo[0] + point[:x],
           memo[1] + point[:y]]
        end

        x = x / 4
        y = y / 4
      end

      if offset_x && offset_y && position == :center
        x = x + offset_x.to_i
        y = y + offset_y.to_i
      end

      [x, y]
    end

    private

    def get_node_quads
      prev_result = get_content_quads

      result = Ferrum.with_attempts(errors: NodeIsMovingError, max: MOVING_ATTEMPTS, wait: 0) do
        sleep(MOVING_WAIT)
        current_result = get_content_quads

        if current_result["quads"] != prev_result["quads"]
          prev_result = current_result
          raise NodeIsMovingError
        end

        current_result
      end

      # FIXME: Case when a few quads returned
      result["quads"].map do |quad|
        [{x: quad[0], y: quad[1]},
         {x: quad[2], y: quad[3]},
         {x: quad[4], y: quad[5]},
         {x: quad[6], y: quad[7]}]
      end.first
    end

    def get_content_quads
      result = page.command("DOM.getContentQuads", nodeId: node_id)
      raise "Node is either not visible or not an HTMLElement" if result["quads"].size == 0
      result
    end
  end
end
