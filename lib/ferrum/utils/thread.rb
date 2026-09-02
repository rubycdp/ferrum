# frozen_string_literal: true

module Ferrum
  module Utils
    #
    # A helper for spawning threads with consistent exception-handling
    # behavior (abort-on-exception and report-on-exception).
    #
    module Thread
      module_function

      #
      # Spawns a new thread running the given block.
      #
      # @param [Boolean] abort_on_exception
      #   Whether the thread aborts the process if it raises an unhandled exception.
      #   Off by default: an exception in one of Ferrum's own threads reaches the
      #   main thread wherever it happens to be, or kills the process outright.
      #
      # @return [Thread]
      #
      def spawn(abort_on_exception: false)
        ::Thread.new(abort_on_exception) do |whether_abort_on_exception|
          ::Thread.current.abort_on_exception = whether_abort_on_exception
          ::Thread.current.report_on_exception = true if ::Thread.current.respond_to?(:report_on_exception=)

          yield
        end
      end
    end
  end
end
