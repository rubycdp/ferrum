# frozen_string_literal: true

module Ferrum
  class Accessibility
    #
    # Represents an [AXNode](https://chromedevtools.github.io/devtools-protocol/tot/Accessibility/#type-AXNode)
    # from the CDP Accessibility domain.
    #
    class AXNode
      #
      # @param [Hash{String => Object}] params
      #   The parsed CDP AXNode attributes.
      #
      def initialize(params)
        @params = deep_freeze(params)
      end

      # The AX node's role, e.g. `"button"`.
      #
      # @return [String, nil]
      def role
        @params.dig("role", "value")
      end

      # The AX node's accessible name.
      #
      # @return [String, nil]
      def name
        @params.dig("name", "value")
      end

      # The AX node's accessible description.
      #
      # @return [String, nil]
      def description
        @params.dig("description", "value")
      end

      # The AX node's current value.
      #
      # @return [String, Numeric, Boolean, nil] raw CDP AXValue.value; type varies by control
      def value
        @params.dig("value", "value")
      end

      # ARIA/computed properties flattened to `name => value`.
      #
      # @return [Hash{String => Object}]
      def properties
        @properties ||= Array(@params["properties"]).to_h do |property|
          [property["name"], property.dig("value", "value")]
        end.freeze
      end

      # Whether the node is ignored by the accessibility tree.
      #
      # @return [Boolean]
      def ignored?
        @params["ignored"] == true
      end

      # The reasons the node is ignored, if any.
      #
      # @return [Array, nil]
      def ignored_reasons
        @params["ignoredReasons"]
      end

      # The AX node's id.
      #
      # @return [String, nil]
      def node_id
        @params["nodeId"]
      end

      # The id of the DOM node this AX node is backed by.
      #
      # @return [Integer, nil]
      def backend_dom_node_id
        @params["backendDOMNodeId"]
      end

      # The ids of this AX node's children.
      #
      # @return [Array, nil]
      def child_ids
        @params["childIds"]
      end

      # The raw CDP AXNode hash.
      #
      # @return [Hash]
      def to_h
        @params
      end

      private

      def deep_freeze(object)
        case object
        when Hash  then object.each { |key, value| deep_freeze(key.freeze) && deep_freeze(value) }
        when Array then object.each { |value| deep_freeze(value) }
        end
        object.freeze
      end
    end
  end
end
