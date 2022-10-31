# frozen_string_literal: true

module Ferrum
  class Cookies
    #
    # Represents a [cookie value](https://chromedevtools.github.io/devtools-protocol/1-3/Network/#type-Cookie).
    #
    class Cookie
      # The parsed JSON attributes.
      #
      # @return [Hash{String => [String, Boolean, nil]}]
      attr_reader :attributes

      #
      # Initializes the cookie.
      #
      # @param [Hash{String => String}] attributes
      #   The parsed JSON attributes.
      #
      def initialize(attributes)
        @attributes = attributes
      end

      #
      # The cookie's name.
      #
      # @return [String]
      #
      def name
        attributes["name"]
      end

      #
      # The cookie's value.
      #
      # @return [String]
      #
      def value
        attributes["value"]
      end

      #
      # The cookie's domain.
      #
      # @return [String]
      #
      def domain
        attributes["domain"]
      end

      #
      # The cookie's path.
      #
      # @return [String]
      #
      def path
        attributes["path"]
      end

      #
      # The `sameSite` configuration.
      #
      # @return ["Strict", "Lax", "None", nil]
      #
      def samesite
        attributes["sameSite"]
      end
      alias same_site samesite

      #
      # The cookie's size.
      #
      # @return [Integer]
      #
      def size
        attributes["size"]
      end

      #
      # Specifies whether the cookie is secure or not.
      #
      # @return [Boolean]
      #
      def secure?
        attributes["secure"]
      end

      #
      # Specifies whether the cookie is HTTP-only or not.
      #
      # @return [Boolean]
      #
      def httponly?
        attributes["httpOnly"]
      end
      alias http_only? httponly?

      #
      # Specifies whether the cookie is a session cookie or not.
      #
      # @return [Boolean]
      #
      def session?
        attributes["session"]
      end

      #
      # Specifies when the cookie will expire.
      #
      # @return [Time, nil]
      #
      def expires
        Time.at(attributes["expires"]) if attributes["expires"].positive?
      end

      #
      # Compares different cookie objects.
      #
      # @return [Boolean]
      #
      def ==(other)
        other.class == self.class && other.attributes == attributes
      end
    end
  end
end
