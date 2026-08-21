# frozen_string_literal: true

module Ferrum
  #
  # Represents an RGBA color, validating that the red/green/blue components
  # are integers between 0 and 255 and that alpha is a float between 0.0 and
  # 1.0. Used e.g. as the background color option for screenshots.
  #
  class RGBA
    def initialize(red, green, blue, alpha)
      self.red = red
      self.green = green
      self.blue = blue
      self.alpha = alpha

      validate
    end

    #
    # Converts the color to a Hash.
    #
    # @return [Hash{Symbol => Integer, Float}]
    #
    def to_h
      { r: red, g: green, b: blue, a: alpha }
    end

    private

    attr_accessor :red, :green, :blue, :alpha

    def validate
      [red, green, blue].each(&method(:validate_color))
      validate_alpha
    end

    def validate_color(value)
      return if value.is_a?(Integer) && Range.new(0, 255).include?(value)

      raise ArgumentError, "Wrong value of #{value} should be Integer from 0 to 255"
    end

    def validate_alpha
      return if alpha.is_a?(Float) && Range.new(0.0, 1.0).include?(alpha)

      raise ArgumentError,
            "Wrong alpha value #{alpha} should be Float between 0.0 (fully transparent) and 1.0 (fully opaque)"
    end
  end
end
