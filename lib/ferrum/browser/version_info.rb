module Ferrum
  class Browser
    class VersionInfo

      def initialize(properties)
        @properties = properties
      end

      def protocol_version
        @properties['protocolVersion']
      end

      def product
        @properties['product']
      end

      def revision
        @properties['revision']
      end

      def user_agent
        @properties['userAgent']
      end

      def js_version
        @properties['jsVersion']
      end

    end
  end
end
