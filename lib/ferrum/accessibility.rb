# frozen_string_literal: true

require "ferrum/accessibility/ax_node"

module Ferrum
  #
  # Wraps the CDP [Accessibility](https://chromedevtools.github.io/devtools-protocol/tot/Accessibility/)
  # domain. The query commands work without `enable`; `enable`/`disable` are
  # provided for completeness (live AX events).
  #
  # @note The node-scoped methods (`node_for`, `partial_tree`, `query` with a
  #   `node:`) issue the command against the node's owning page session. They
  #   support same-process (same-target) iframes; nodes living in an
  #   out-of-process iframe (OOPIF, separate CDP target) are not resolvable and
  #   will error or return an empty result.
  #
  class Accessibility
    def initialize(page)
      @page = page
    end

    #
    # The single non-ignored AXNode for a DOM node, or `nil`.
    #
    # @param [Ferrum::Node] node
    # @return [AXNode, nil]
    #
    def node_for(node)
      partial_tree(node: node).find { |ax_node| !ax_node.ignored? }
    end

    #
    # The partial AX tree for a DOM node.
    #
    # @param [Ferrum::Node] node
    # @param [Boolean] fetch_relatives
    # @return [Array<AXNode>]
    #
    # @raise [TimeoutError]
    #
    def partial_tree(node:, fetch_relatives: false)
      nodes = node.page.command("Accessibility.getPartialAXTree",
                                nodeId: node.node_id,
                                fetchRelatives: fetch_relatives)["nodes"]
      build(nodes)
    end

    #
    # The full AX tree for the page.
    #
    # @param [Integer, nil] depth
    # @param [String, nil] frame_id
    # @return [Array<AXNode>]
    #
    # @raise [TimeoutError]
    #
    def snapshot(depth: nil, frame_id: nil)
      params = { depth: depth, frameId: frame_id }.compact
      build(@page.command("Accessibility.getFullAXTree", **params)["nodes"])
    end

    #
    # Query the AX tree by accessible name and/or role.
    #
    # @param [String, nil] name
    # @param [String, nil] role
    # @param [Ferrum::Node, nil] node  Scope the query to this node's subtree.
    # @return [Array<AXNode>]
    #
    # @raise [TimeoutError]
    #
    def query(name: nil, role: nil, node: nil)
      page = node ? node.page : @page
      params = { accessibleName: name, role: role }.compact
      params[:nodeId] = node ? node.node_id : page.document_node_id
      build(page.command("Accessibility.queryAXTree", **params)["nodes"])
    end

    #
    # The root AXNode of the (optionally framed) document.
    #
    # @param [String, nil] frame_id
    # @return [AXNode, nil]
    #
    # @raise [TimeoutError]
    #
    def root(frame_id: nil)
      params = { depth: 1, frameId: frame_id }.compact
      build(@page.command("Accessibility.getFullAXTree", **params)["nodes"]).first
    end

    #
    # Turns the Accessibility domain on or off. Only needed for its live AX
    # events, the query methods work without it.
    #
    # @param [Boolean] enabled
    #
    # @raise [TimeoutError]
    #
    # @example
    #   page.accessibility.enabled = true
    #   page.on("Accessibility.nodesUpdated") { |params| puts params["nodes"].size }
    #
    def enabled=(enabled)
      @page.command(enabled ? "Accessibility.enable" : "Accessibility.disable")
    end

    #
    # @deprecated Will be removed in Ferrum 0.22. Use `enabled = true`.
    #
    # @return [self]
    #
    # @raise [TimeoutError]
    #
    def enable
      Utils::Deprecate.warn("accessibility.enable will be removed in Ferrum 0.22. Use enabled = true instead.",
                            user_code: true)
      tap { self.enabled = true }
    end

    #
    # @deprecated Will be removed in Ferrum 0.22. Use `enabled = false`.
    #
    # @return [self]
    #
    # @raise [TimeoutError]
    #
    def disable
      Utils::Deprecate.warn("accessibility.disable will be removed in Ferrum 0.22. Use enabled = false instead.",
                            user_code: true)
      tap { self.enabled = false }
    end

    private

    def build(nodes)
      Array(nodes).map { |node| AXNode.new(node) }
    end
  end
end
