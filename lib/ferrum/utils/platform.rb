# frozen_string_literal: true

module Ferrum
  module Utils
    module Platform
      module_function

      #
      # Detects the current platform.
      #
      # @return [:mac, :windows, :linux]
      #
      def platform_name
        return :mac if mac?
        return :windows if windows?

        :linux
      end

      # Whether the current platform is Windows.
      #
      # @return [Boolean]
      def windows?
        RbConfig::CONFIG["host_os"] =~ /mingw|mswin|cygwin/
      end

      # Whether the current platform is macOS.
      #
      # @return [Boolean]
      def mac?
        RbConfig::CONFIG["host_os"] =~ /darwin/
      end

      # Whether the current platform is macOS running on Apple Silicon (arm64).
      #
      # @return [Boolean]
      def mac_arm?
        mac? && RbConfig::CONFIG["host_cpu"] =~ /arm/
      end

      # Whether the current Ruby engine is MRI (as opposed to e.g. JRuby, TruffleRuby).
      #
      # @return [Boolean]
      def mri?
        defined?(RUBY_ENGINE) && RUBY_ENGINE == "ruby"
      end
    end
  end
end
