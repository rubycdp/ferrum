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
        # FIXME: check node type and remove static 1
        node_id = within&.node_id || 1

        ids = command("DOM.querySelectorAll",
                      nodeId: node_id,
                      selector: selector)["nodeIds"]
        ids.map { |id| _build_node(id) }.compact
      end

      def at_css(selector, within: nil)
        # FIXME: check node type and remove static 1
        node_id = within&.node_id || 1

        id = command("DOM.querySelector",
                     nodeId: node_id,
                     selector: selector)["nodeId"]
        _build_node(id)
      end

      private

      def _build_node(node_id)
        description = command("DOM.describeNode", nodeId: node_id)
        Node.new(self, target_id, node_id, description["node"])
      end
    end
  end
end
