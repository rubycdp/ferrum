# frozen_string_literal: true

module Ferrum
  module Utils
    #
    # Emits deprecation warnings for the JavaScript evaluation API, whose
    # old behavior is removed in the next release, Ferrum 0.21.
    #
    # Warnings are printed once per unique message and call site so that a
    # deprecated call inside a loop doesn't flood the output. Set
    # `FERRUM_DEPRECATION_WARNINGS=0` to silence them entirely, or
    # `FERRUM_DEPRECATION_WARNINGS=raise` to turn them into errors while
    # migrating a suite.
    #
    module Deprecate
      @seen = Concurrent::Set.new

      module_function

      #
      # Warns about a deprecation, naming where it comes from.
      #
      # @param [String] message
      #   What changes, and what to do instead.
      #
      # @param [Boolean] user_code
      #   Whether to name the first caller outside any installed gem, which is
      #   where a script passed through a library like Capybara was written,
      #   rather than the direct caller.
      #
      # @return [void]
      #
      # @raise [Ferrum::Error]
      #   When `FERRUM_DEPRECATION_WARNINGS=raise`.
      #
      def warn(message, user_code: false)
        mode = ENV.fetch("FERRUM_DEPRECATION_WARNINGS", "warn")
        return if %w[0 false].include?(mode)

        location = caller_locations(1)&.find { |frame| !skip?(frame.path.to_s, user_code) }
        message = "[Ferrum] DEPRECATION: #{message}"
        message += "\n  called from #{location.path}:#{location.lineno}" if location

        raise Ferrum::Error, message if mode == "raise"
        return unless @seen.add?(message)

        Kernel.warn(message)
      end

      #
      # Forgets which warnings have already been printed. Only useful in tests.
      #
      # @return [void]
      #
      def reset!
        @seen.clear
      end

      #
      # Whether a caller's path is left out when naming where a deprecated
      # call comes from.
      #
      # @param [String] path
      #
      # @param [Boolean] user_code
      #   Whether to leave out installed gems as well as Ferrum itself.
      #
      # @return [Boolean]
      #
      def skip?(path, user_code)
        return true if path.include?("/lib/ferrum/") || path.end_with?("forwardable.rb") || path.start_with?("<")

        user_code && Gem.path.any? { |gem_path| path.start_with?(File.join(gem_path, "")) }
      end
    end
  end
end
