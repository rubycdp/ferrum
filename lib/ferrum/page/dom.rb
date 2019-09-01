# frozen_string_literal: true

module Ferrum
  class Page
    module DOM
      def current_url
        evaluate("window.top.location.href")
      end

      def title
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
          }), timeout, selector, within)
      end

      def css(selector, within: nil)
        node_id = within&.node_id || @document_id

        ids = command("DOM.querySelectorAll",
                      nodeId: node_id,
                      selector: selector)["nodeIds"]
        ids.map { |id| build_node(id) }.compact
      end

      def at_css(selector, within: nil)
        node_id = within&.node_id || @document_id

        id = command("DOM.querySelector",
                     nodeId: node_id,
                     selector: selector)["nodeId"]
        build_node(id)
      end

      private

      def build_node(node_id)
        description = command("DOM.describeNode", nodeId: node_id)
        Node.new(self, target_id, node_id, description["node"])
      end
    end
  end
end
