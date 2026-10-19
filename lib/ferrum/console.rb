# frozen_string_literal: true

require "ferrum/console/message"

module Ferrum
  #
  # Collects what the DevTools console would show for a page or worker:
  # `console.*` calls, browser log entries and uncaught exceptions, as
  # {Console::Message}s. Keeps the last {LIMIT} messages and is `Enumerable`
  # over them, oldest first.
  #
  # @example
  #   browser.go_to("https://example.com")
  #   browser.console.select(&:error?) # => [#<Ferrum::Console::Message type=:error ...>]
  #   browser.console.clear
  #
  class Console
    include Enumerable

    LIMIT = 1000

    def initialize(page)
      @page = page
      @messages = []
      @listeners = Concurrent::Map.new
      @listener_id = Concurrent::AtomicFixnum.new
      @mutex = Mutex.new
    end

    #
    # Yields each collected message, oldest first.
    #
    # @yieldparam [Message] message
    #
    # @return [Enumerator, self]
    #
    def each(&)
      return to_enum(:each) { size } unless block_given?

      to_a.each(&)
      self
    end

    #
    # The collected messages, oldest first.
    #
    # @return [Array<Message>]
    #
    def to_a
      @mutex.synchronize { @messages.dup }
    end

    #
    # The most recent message.
    #
    # @return [Message, nil]
    #
    def last
      @mutex.synchronize { @messages.last }
    end

    #
    # Number of collected messages.
    #
    # @return [Integer]
    #
    def size
      @mutex.synchronize { @messages.size }
    end

    #
    # Whether no messages were collected.
    #
    # @return [Boolean]
    #
    def empty?
      size.zero?
    end

    #
    # Forgets the collected messages.
    #
    # @return [self]
    #
    def clear
      @mutex.synchronize { @messages.clear }
      self
    end

    #
    # Calls the block for every new message. Prefer `page.on(:console)`.
    #
    # @yieldparam [Message] message
    #
    # @return [Integer]
    #   The listener id, used to remove it via {#off}.
    #
    def on(&block)
      @listener_id.increment.tap { |id| @listeners[id] = block }
    end

    #
    # Removes a listener added via {#on}.
    #
    # @param [Integer] id
    #
    # @return [void]
    #
    def off(id)
      @listeners.delete(id)
    end

    #
    # Subscribes to the CDP events messages are built from.
    #
    # @return [void]
    #
    def subscribe
      @page.on("Runtime.consoleAPICalled") do |params|
        add(Message.from_console_api(params)) unless replayed?(params)
      end

      @page.on("Log.entryAdded") do |params|
        entry = params["entry"]
        add(Message.from_log_entry(entry)) unless entry["source"] == "worker"
      end

      @page.on("Runtime.exceptionThrown") do |params|
        add(Message.from_exception(params))
      end
    end

    #
    # Debug representation of the console.
    #
    # @return [String]
    #
    def inspect
      "#<#{self.class.name} size=#{size}>"
    end

    private

    def replayed?(params)
      params["executionContextId"].to_i.zero?
    end

    def add(message)
      @mutex.synchronize do
        @messages << message
        @messages.shift if @messages.size > LIMIT
      end

      @listeners.each_value { |listener| listener.call(message) }
    end
  end
end
