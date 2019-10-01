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

      def body
        evaluate("document.documentElement.outerHTML")
      end

      def at_xpath(selector, within: nil)
        xpath(selector, within: within).first
      end

      # FIXME: Check within
      def xpath(selector, within: nil)
        evaluate_async(%(
          try {
            let selector = arguments[0];
            let within = arguments[1] || document;
            let results = [];

            let xpath = document.evaluate(selector, within, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
            for (let i = 0; i < xpath.snapshotLength; i++) {
              results.push(xpath.snapshotItem(i));
            }

            arguments[2](results);
          } catch (error) {
            // DOMException.INVALID_EXPRESSION_ERR is undefined, using pure code
            if (error.code == DOMException.SYNTAX_ERR || error.code == 51) {
              throw "Invalid Selector";
            } else {
              throw error;
            }
          }), @page.timeout, selector, within)
      end

      # FIXME css doesn't work for a frame w/o execution_id
      def css(selector, within: nil)
        node_id = within&.node_id || @page.document_id

        ids = @page.command("DOM.querySelectorAll",
                            nodeId: node_id,
                            selector: selector)["nodeIds"]
        ids.map { |id| build_node(id) }.compact
      end

      def at_css(selector, within: nil)
        node_id = within&.node_id || @page.document_id

        id = @page.command("DOM.querySelector",
                     nodeId: node_id,
                     selector: selector)["nodeId"]
        build_node(id)
      end

      private

      def build_node(node_id)
        description = @page.command("DOM.describeNode", nodeId: node_id)
        Node.new(self, @page.target_id, node_id, description["node"])
      end
    end
  end
end
