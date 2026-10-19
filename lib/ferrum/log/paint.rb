# frozen_string_literal: true

module Ferrum
  class Log
    #
    # Wraps text in basic ANSI colors, which terminal themes adapt to light
    # and dark backgrounds, when the includer's `@color` is set.
    #
    module Paint
      COLORS = { bold: 1, dim: 2, red: 31, green: 32, yellow: 33, magenta: 35, cyan: 36 }.freeze

      # Whether text gets colored.
      #
      # @return [Boolean]
      def color?
        @color
      end

      private

      def paint(text, color)
        return text.to_s unless color && color?

        "\e[#{COLORS.fetch(color)}m#{text}\e[0m"
      end
    end
  end
end
