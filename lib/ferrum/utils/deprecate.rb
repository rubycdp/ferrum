# frozen_string_literal: true

module Ferrum
  module Utils
    #
    # Emits deprecation warnings for the legacy JavaScript evaluation API.
    #
    # Warnings are printed once per unique message and call site so that a
    # deprecated call inside a loop doesn't flood the output. Set
    # `FERRUM_DEPRECATION_WARNINGS=0` to silence them entirely, or
    # `FERRUM_DEPRECATION_WARNINGS=raise` to turn them into errors while
    # migrating a suite.
    #
    module Deprecate
      MODE = ENV.fetch("FERRUM_DEPRECATION_WARNINGS", "warn")

      @seen = Concurrent::Set.new

      module_function

      #
      # Warns that `old` is deprecated and should be replaced by `new`.
      #
      # @param [String] old
      #   The deprecated call, e.g. `"Ferrum::Frame#evaluate_async"`.
      #
      # @param [String] new
      #   What to use instead.
      #
      # @return [void]
      #
      def warn(old, new)
        return if MODE == "0" || MODE == "false"

        location = caller_locations(2, 20)&.find do |frame|
          !frame.path.include?("/lib/ferrum/") && !frame.path.end_with?("forwardable.rb")
        end
        message = "[Ferrum] DEPRECATION: #{old} is deprecated and will be removed in the next major " \
                  "release. #{new}"
        message += "\n  called from #{location.path}:#{location.lineno}" if location

        raise Ferrum::Error, message if MODE == "raise"
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
    end
  end
end
