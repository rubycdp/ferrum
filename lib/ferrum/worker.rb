# frozen_string_literal: true

require "ferrum/frame/runtime"
require "ferrum/interceptable"

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

    attr_reader :target_id, :url

    def initialize(client, target_id:, url:)
      @client = client
      @target_id = target_id
      @url = url
      @options = client.options
      @page = self
      @execution_id = Concurrent::MVar.new
      @network = Network.new(self)

      subscribe
      prepare
    end

    # Network object.
    #
    # @return [Network]
    attr_reader :network

    # How long to wait for CDP responses and JS evaluation to complete.
    #
    # @return [Numeric]
    def timeout
      @options.timeout
    end

    # Sends a CDP command through {#client}.
    #
    # @return [Boolean, Hash]
    #   `true` when sent asynchronously, otherwise the command's result.
    def command(...)
      client.command(...)
    end

    # Workers have a single execution context and no navigable document, so
    # there's nothing for {Network} to check requests against.
    def main_frame
      nil
    end

    # Closes the target in the browser, and its connection.
    #
    # @return [Boolean]
    def close
      client.command("Target.closeTarget", async: true, targetId: target_id)
      close_connection

      true
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

      on("Runtime.executionContextCreated") do |params|
        self.execution_id = params.dig("context", "id")
      end

      return unless @options.js_errors

      on("Runtime.exceptionThrown") do |params|
        # FIXME: https://jvns.ca/blog/2015/11/27/why-rubys-timeout-is-dangerous-and-thread-dot-raise-is-terrifying/
        Thread.main.raise JavaScriptError, params["exceptionDetails"]
      end
    end

    def prepare
      command("Runtime.enable")
      command("Network.enable")
      command("Runtime.runIfWaitingForDebugger")
    end

    def execution_id!
      value = @execution_id.borrow(timeout, &:itself)
      raise NoExecutionContextError if value.instance_of?(Object)

      value
    end

    def execution_id=(value)
      if value.nil?
        @execution_id.try_take!
      else
        @execution_id.try_put!(value)
      end
    end
  end
end
