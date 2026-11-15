# frozen_string_literal: true

module Ferrum
  #
  # A point in time by which an operation has to finish, on the monotonic
  # clock. One deadline is shared by every step of an operation, so the whole
  # operation is bounded by a single budget instead of each step getting its
  # own.
  #
  # @example
  #   deadline = Ferrum::Deadline.after(10)
  #   deadline.remaining # => 9.99
  #   deadline.expired?  # => false
  #
  class Deadline
    #
    # Starts a deadline that expires in `seconds`.
    #
    # @param [Numeric] seconds
    #
    # @return [Deadline]
    #
    def self.after(seconds)
      new(Utils::ElapsedTime.monotonic_time + seconds)
    end

    #
    # Returns a {Deadline} as is, and starts one for a number of seconds.
    #
    # @param [Deadline, Numeric] timeout
    #
    # @return [Deadline]
    #
    def self.wrap(timeout)
      timeout.is_a?(self) ? timeout : after(timeout)
    end

    #
    # @param [Float] at
    #   Monotonic time at which the deadline expires.
    #
    def initialize(at)
      @at = at
    end

    #
    # Seconds left before the deadline expires, never negative.
    #
    # @return [Float]
    #
    def remaining
      [@at - Utils::ElapsedTime.monotonic_time, 0.0].max
    end

    #
    # Whether the deadline has expired.
    #
    # @return [Boolean]
    #
    def expired?
      remaining.zero?
    end
  end
end
