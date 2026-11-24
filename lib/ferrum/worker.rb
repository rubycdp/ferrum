# frozen_string_literal: true

require "ferrum/frame/runtime"
require "ferrum/interceptable"
require "ferrum/console"

module Ferrum
  # A dedicated or shared Worker spawned by a page. Unlike {Page} it has no
  # DOM, frames, mouse/keyboard, or navigation history -- just a single
  # global execution context and its own network activity.
  class Worker
    include Frame::Runtime
    include Interceptable

    # Client connection.
    #
    # @return [Client, SessionClient]
    attr_reader :client

    attr_reader :target_id, :url, :type

    def initialize(client, target_id:, url:, type: "worker")
      @client = client
      @target_id = target_id
      @url = url
      @type = type
      @options = client.options
      @page = self
      @execution_id = Concurrency::Cell.new
      @network = Network.new(self)
      @console = Console.new(self)

      subscribe
      prepare
    end

    # Network object.
    #
    # @return [Network]
    attr_reader :network

    # Console messages.
    #
    # @return [Console]
    attr_reader :console

    # How long to wait for CDP responses and JS evaluation to complete.
    #
    # @return [Numeric]
    def timeout
      @options.timeout
    end

    # Sends a CDP command through {#client}.
    #
    # @param [String] method
    #   The CDP method name.
    #
    # @param [Numeric, Deadline, nil] timeout
    #   How long to wait for the response, the worker's `timeout` by default.
    #
    # @param [Hash] params
    #   The command's parameters.
    #
    # @return [Hash]
    #   The command's result.
    #
    # @raise [TimeoutError]
    def command(method, timeout: nil, **params)
      client.command(method, timeout: timeout || self.timeout, **params)
    end

    # Workers have a single execution context and no navigable document, so
    # there's nothing for {Network} to check requests against.
    def main_frame
      nil
    end

    # Closes the worker in the browser, and its connection. Chrome refuses
    # `Target.closeTarget` for a dedicated worker, so it closes itself instead.
    #
    # @return [nil]
    def close
      if type == "worker"
        client.notify("Runtime.evaluate", expression: "self.close()")
      else
        client.notify("Target.closeTarget", targetId: target_id)
      end
      close_connection

      nil
    end

    # Closes the WebSocket connection only, without asking the browser to
    # close the underlying target. Kept separate from {#close} so a whole
    # context can be dropped (the browser closes its targets anyway) without
    # every worker having to be closed one by one.
    #
    # @return [void]
    def close_connection
      client&.close
    end

    # Debug representation of the worker.
    #
    # @return [String]
    def inspect
      "#<#{self.class} @target_id=#{@target_id.inspect} @url=#{@url.inspect}>"
    end

    private

    def subscribe
      network.subscribe
      console.subscribe

      on("Runtime.executionContextCreated") do |params|
        self.execution_id = params.dig("context", "id")
      end
    end

    def prepare
      command("Runtime.enable")
      command("Network.enable")
      command("Runtime.runIfWaitingForDebugger")
    end

    def execution_id!(timeout = nil)
      @execution_id.wait(timeout || self.timeout)
      @execution_id.value || raise(NoExecutionContextError)
    end

    def execution_id=(value)
      if value.nil?
        @execution_id.clear
      elsif !@execution_id.set?
        @execution_id.set(value)
      end
    end
  end
end
