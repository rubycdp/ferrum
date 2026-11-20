# frozen_string_literal: true

module Ferrum
  module Utils
    #
    # The loop behind every `wait_*` method: runs a block until it returns a
    # truthy value or the timeout is reached, sleeping between the attempts.
    #
    module Poll
      module_function

      #
      # Runs the block until it returns a truthy value. Calls in the block
      # share the timeout, see {Deadline.within}.
      #
      # @param [Numeric, Deadline] timeout
      #   How long to keep trying.
      #
      # @param [Numeric] interval
      #   Seconds to sleep between the attempts.
      #
      # @yield The check to repeat.
      #
      # @return [Object, nil]
      #   What the block returned, `nil` if it didn't return a truthy value in time.
      #
      def call(timeout, interval, &)
        deadline = Deadline.wrap(timeout)
        Deadline.within(deadline) do
          loop do
            value = attempt(deadline, &)
            return value if value
            return if deadline.expired?

            sleep([interval, deadline.remaining].min)
          end
        end
      end

      #
      # Runs the block once, turning a {TimeoutError} it raises into `nil`
      # once the deadline has expired.
      #
      # @param [Deadline] deadline
      #
      # @return [Object, nil]
      #
      def attempt(deadline)
        yield
      rescue TimeoutError
        raise unless deadline.expired?

        nil
      end
    end
  end
end
