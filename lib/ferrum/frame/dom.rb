# frozen_string_literal: true

# RemoteObjectId is from a JavaScript world, and corresponds to any JavaScript
# object, including JS wrappers for DOM nodes. There is a way to convert between
# node ids and remote object ids (DOM.requestNode and DOM.resolveNode).
#
# NodeId is used for inspection, when backend tracks the node and sends updates to
# the frontend. If you somehow got NodeId over protocol, backend should have
# pushed to the frontend all of it's ancestors up to the Document node via
# DOM.setChildNodes. After that, frontend is always kept up-to-date about anything
# happening to the node.
#
# BackendNodeId is just a unique identifier for a node. Obtaining it does not send
# any updates, for example, the node may be destroyed without any notification.
# This is a way to keep a reference to the Node, when you don't necessarily want
# to keep track of it. One example would be linking to the node from performance
# data (e.g. relayout root node). BackendNodeId may be either resolved to
# inspected node (DOM.pushNodesByBackendIdsToFrontend) or described in more
# details (DOM.describeNode).
module Ferrum
  class Frame
    module DOM
      def current_url
        evaluate("window.top.location.href")
      end

      def current_title
        evaluate("window.top.document.title")
      end

      def doctype
        evaluate("document.doctype && new XMLSerializer().serializeToString(document.doctype)")
      end

      def body
        evaluate("document.documentElement.outerHTML")
      end

      #
      # Finds nodes by using a XPath selector.
      #
      # @param [String] selector
      #   The XPath selector.
      #
      # @param [Node, nil] within
      #   The parent node to search within.
      #
      # @return [Array<Node>]
      #   The matching nodes.
      #
      # @example
      #   browser.go_to("https://github.com/")
      #   browser.xpath("//a[@aria-label='Issues you created']") # => [Node]
      #
      def xpath(selector, within: nil)
        expr = <<~JS
          function(selector, within) {
            let results = [];
            within ||= document

            let xpath = document.evaluate(selector, within, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
            for (let i = 0; i < xpath.snapshotLength; i++) {
              results.push(xpath.snapshotItem(i));
            }

            return results;
          }
        JS

        evaluate_func(expr, selector, within)
      end

      #
      # Finds a node by using a XPath selector.
      #
      # @param [String] selector
      #   The XPath selector.
      #
      # @param [Node, nil] within
      #   The parent node to search within.
      #
      # @return [Node, nil]
      #   The matching node.
      #
      # @example
      #   browser.go_to("https://github.com/")
      #   browser.at_xpath("//a[@aria-label='Issues you created']") # => Node
      #
      def at_xpath(selector, within: nil)
        expr = <<~JS
          function(selector, within) {
            within ||= document
            let xpath = document.evaluate(selector, within, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
            return xpath.snapshotItem(0);
          }
        JS
        evaluate_func(expr, selector, within)
      end

      #
      # Finds nodes by using a CSS path selector.
      #
      # @param [String] selector
      #   The CSS path selector.
      #
      # @param [Node, nil] within
      #   The parent node to search within.
      #
      # @return [Array<Node>]
      #   The matching nodes.
      #
      # @example
      #   browser.go_to("https://github.com/")
      #   browser.css("a[aria-label='Issues you created']") # => [Node]
      #
      def css(selector, within: nil)
        expr = <<~JS
          function(selector, within) {
            within ||= document
            return Array.from(within.querySelectorAll(selector));
          }
        JS

        evaluate_func(expr, selector, within)
      end

      #
      # Finds a node by using a CSS path selector.
      #
      # @param [String] selector
      #   The CSS path selector.
      #
      # @param [Node, nil] within
      #   The parent node to search within.
      #
      # @return [Node, nil]
      #   The matching node.
      #
      # @example
      #   browser.go_to("https://github.com/")
      #   browser.at_css("a[aria-label='Issues you created']") # => Node
      #
      def at_css(selector, within: nil)
        expr = <<~JS
          function(selector, within) {
            within ||= document
            return within.querySelector(selector);
          }
        JS

        evaluate_func(expr, selector, within)
      end
    end
  end
end
