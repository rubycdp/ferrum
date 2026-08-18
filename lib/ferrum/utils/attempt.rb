# frozen_string_literal: true

module Ferrum
  module Utils
    module Attempt
      module_function

      #
      # Retries the block up to `max` times when one of `errors` is raised,
      # sleeping `wait` seconds between attempts.
      #
      # @param [Array<Class>, Class] errors
      #   Exception classes that trigger a retry.
      #
      # @param [Integer] max
      #   Maximum number of attempts.
      #
      # @param [Numeric] wait
      #   Seconds to sleep between attempts.
      #
      # @return [Object]
      #
      def with_retry(errors:, max:, wait:)
        attempts ||= 1
        yield
      rescue *Array(errors)
        raise if attempts >= max

        attempts += 1
        sleep(wait)
        retry
      end
    end
  end
end
