# frozen_string_literal: true

module Ferrum
  class Node
    attr_reader :page, :target_id, :node_id, :description

    def initialize(page, target_id, node_id, description)
      @page, @target_id, @node_id, @description =
        page, target_id, node_id, description
    end

    def node?
      description["nodeType"] == 1 # nodeType: 3, nodeName: "#text" e.g.
    end

    def page_send(name, *args)
      page.send(name, self, *args)
    rescue BrowserError => e
      case e.message
      when "No node with given id found"
        raise ObsoleteNode.new(self, e.response)
      else
        raise
      end
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
      page.evaluate_on(node: self, expression: "this.textContent")
    end

    def property(name)
      page_send(:property, name)
    end

    def [](name)
      # Although the attribute matters, the property is consistent. Return that in
      # preference to the attribute for links and images.
      if ((tag_name == "img") && (name == "src")) || ((tag_name == "a") && (name == "href"))
        # if attribute exists get the property
        return page_send(:attribute, name) && page_send(:property, name)
      end

      value = property(name)
      value = page_send(:attribute, name) if value.nil? || value.is_a?(Hash)

      value
    end

    def attributes
      page_send(:attributes)
    end

    def value
      page.evaluate_on(node: self, expression: "this.value")
    end

    def set(value)
      if tag_name == "input"
        case self[:type]
        when "radio"
          click
        when "checkbox"
          click if value != checked?
        when "file"
          files = value.respond_to?(:to_ary) ? value.to_ary.map(&:to_s) : value.to_s
          page_send(:select_file, files)
        else
          page_send(:set, value.to_s)
        end
      elsif tag_name == "textarea"
        page_send(:set, value.to_s)
      elsif self[:isContentEditable]
        # FIXME:
        page_send(:delete_text)
        send_keys(value.to_s)
      end
    end

    def select_option
      page_send(:select, true)
    end

    def unselect_option
      raise NotImplemented
    end

    def tag_name
      @tag_name ||= description["nodeName"].downcase
    end

    def visible?
      page_send(:visible?)
    end

    def checked?
      self[:checked]
    end

    def selected?
      !!self[:selected]
    end

    def disabled?
      page_send(:disabled?)
    end

    def click(keys = [], offset = {})
      page_send(:click, keys, offset)
    end

    def right_click(keys = [], offset = {})
      page_send(:right_click, keys, offset)
    end

    def double_click(keys = [], offset = {})
      page_send(:double_click, keys, offset)
    end

    def hover
      page_send(:hover)
    end

    def trigger(event)
      page_send(:trigger, event)
    end

    def scroll_to(element, location, position = nil)
      if element.is_a?(Node)
        scroll_element_to_location(element, location)
      elsif location.is_a?(Symbol)
        scroll_to_location(location)
      else
        scroll_to_coords(*position)
      end
      self
    end

    def ==(other)
      return false unless other.is_a?(Node)
      # We compare backendNodeId because once nodeId is sent to frontend backend
      # never returns same nodeId sending 0. In other words frontend is
      # responsible for keeping track of node ids.
      target_id == other.target_id && description["backendNodeId"] == other.description["backendNodeId"]
    end

    def send_keys(*keys)
      page_send(:send_keys, keys)
    end
    alias_method :send_key, :send_keys

    def path
      page_send(:path)
    end

    def inspect
      %(#<#{self.class} @target_id=#{@target_id.inspect} @node_id=#{@node_id} @description=#{@description.inspect}>)
    end
  end
end
