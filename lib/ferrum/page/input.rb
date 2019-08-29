# frozen_string_literal: true

require "json"

module Ferrum
  class Page
    module Input
      def scroll_to(top, left)
        execute("window.scrollTo(#{top}, #{left})")
      end

      def find_position(node, offset_x = nil, offset_y = nil)
        quads = get_content_quads(node)
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

      def get_content_quads(node)
        result = command("DOM.getContentQuads", nodeId: node.node_id)
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
end
