# frozen_string_literal: true

module Ferrum
  module Utils
    module Platform
      module_function

      def windows?
        RbConfig::CONFIG["host_os"] =~ /mingw|mswin|cygwin/
      end

      def mac?
        RbConfig::CONFIG["host_os"] =~ /darwin/
      end

      def mri?
        defined?(RUBY_ENGINE) && RUBY_ENGINE == "ruby"
      end
    end
  end
end
