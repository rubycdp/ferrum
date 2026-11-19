# frozen_string_literal: true

module Ferrum
  #
  # A point in time by which an operation has to finish, on the monotonic
  # clock. One deadline is shared by every step of an operation, so the whole
  # operation is bounded by a single budget instead of each step getting its
  # own.
  #
  # A deadline can be set for a block with {.within}, then every call made in it, by the same thread, runs under
  # whatever is left of it. A call can only shorten that budget, never extend it.
  #
  # @example
  #   deadline = Ferrum::Deadline.after(10)
  #   deadline.remaining # => 9.99
  #   deadline.expired?  # => false
  #
  # @example
  #   Ferrum::Deadline.within(10) do
  #     page.go_to("https://example.com")
  #     page.cookies.to_a
  #     page.evaluate("document.title")
  #   end
  #
  class Deadline
    THREAD_KEY = :ferrum_deadline

    #
    # The deadline set by the enclosing {.within} block of this thread.
    #
    # @return [Deadline, nil]
    #
    def self.current
      Thread.current.thread_variable_get(THREAD_KEY)
    end

    #
    # Runs the block with every Ferrum call made by this thread bound by the same budget. A block inside another
    # one can only shorten it. Other threads, event callbacks for instance, don't inherit it.
    #
    # @param [Numeric, Deadline] timeout
    #
    # @return [Object]
    #   What the block returns.
    #
    # @raise [TimeoutError]
    #   From the calls in the block once the budget is used up.
    #
    def self.within(timeout)
      previous = current
      Thread.current.thread_variable_set(THREAD_KEY, wrap(timeout))
      yield
    ensure
      Thread.current.thread_variable_set(THREAD_KEY, previous)
    end

    #
    # Runs the block outside the budget of the enclosing {.within} block, for cleanup that has to reach the browser
    # even when the budget is used up, like releasing a held key. The calls in it follow their own timeouts.
    #
    # @api private
    #
    # @return [Object]
    #   What the block returns.
    #
    def self.suspend
      previous = current
      Thread.current.thread_variable_set(THREAD_KEY, nil)
      yield
    ensure
      Thread.current.thread_variable_set(THREAD_KEY, previous)
    end

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
    # Returns a {Deadline} as is, and starts one for a number of seconds. Within a {.within} block it returns
    # whichever of the two expires first.
    #
    # @param [Deadline, Numeric] timeout
    #
    # @return [Deadline]
    #
    def self.wrap(timeout)
      deadline = timeout.is_a?(self) ? timeout : after(timeout)
      ambient = current
      ambient ? deadline.min(ambient) : deadline
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
    # The one of the two deadlines that expires first.
    #
    # @param [Deadline] other
    #
    # @return [Deadline]
    #
    def min(other)
      at <= other.at ? self : other
    end

    #
    # Whether the deadline has expired.
    #
    # @return [Boolean]
    #
    def expired?
      remaining.zero?
    end

    protected

    attr_reader :at
  end
end
