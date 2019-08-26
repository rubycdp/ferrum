# frozen_string_literal: true

module Ferrum
  class Page
    module DOM
      def current_url
        evaluate_in(execution_context_id, "window.top.location.href")
      end

      def title
        evaluate_in(execution_context_id, "window.top.document.title")
      end

      def body
        evaluate("document.documentElement.outerHTML")
      end

      def property(node, name)
        evaluate_on(node: node, expression: %Q(this["#{name}"]))
      end

      def select_file(node, value)
        command("DOM.setFileInputFiles", nodeId: node.node_id, files: Array(value))
      end

      def at_xpath(selector, within: nil)
        raise NotImplemented
      end

      def xpath(selector, within: nil)
        raise NotImplemented
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
      rescue BrowserError => e
        node_id.zero? ? raise(NodeError.new(nil, e.response)) : raise
      end
    end
  end
end
