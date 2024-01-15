# frozen_string_literal: true

require "ferrum/context"

module Ferrum
  class Contexts
    include Enumerable

    attr_reader :contexts

    def initialize(client)
      @contexts = Concurrent::Map.new
      @client = client
      subscribe
      auto_attach
      discover
    end

    def default_context
      @default_context ||= create
    end

    def each(&block)
      return enum_for(__method__) unless block_given?

      @contexts.each(&block)
    end

    def [](id)
      @contexts[id]
    end

    def find_by(target_id:)
      context = nil
      @contexts.each_value { |c| context = c if c.target?(target_id) }
      context
    end

    def create(**options)
      response = @client.command("Target.createBrowserContext", **options)
      context_id = response["browserContextId"]
      context = Context.new(@client, self, context_id)
      @contexts[context_id] = context
      context
    end

    def dispose(context_id)
      context = @contexts[context_id]
      context.close_targets_connection
      @client.command("Target.disposeBrowserContext", browserContextId: context.id)
      @contexts.delete(context_id)
      true
    end

    def close_connections
      @contexts.each_value(&:close_targets_connection)
    end

    def reset
      @default_context = nil
      @contexts.each_key { |id| dispose(id) }
    end

    def size
      @contexts.size
    end

    private

    def subscribe
      @client.on("Target.attachedToTarget") do |params|
        info, session_id = params.values_at("targetInfo", "sessionId")
        next unless info["type"] == "page"

        context_id = info["browserContextId"]
        @contexts[context_id]&.add_target(session_id: session_id, params: info)
        if params["waitingForDebugger"]
          @client.session(session_id).command("Runtime.runIfWaitingForDebugger", async: true)
        end
      end

      @client.on("Target.targetCreated") do |params|
        info = params["targetInfo"]
        next unless info["type"] == "page"

        context_id = info["browserContextId"]
        @contexts[context_id]&.add_target(params: info)
      end

      @client.on("Target.targetInfoChanged") do |params|
        info = params["targetInfo"]
        next unless info["type"] == "page"

        context_id, target_id = info.values_at("browserContextId", "targetId")
        @contexts[context_id]&.update_target(target_id, info)
      end

      @client.on("Target.targetDestroyed") do |params|
        context = find_by(target_id: params["targetId"])
        context&.delete_target(params["targetId"])
      end

      @client.on("Target.targetCrashed") do |params|
        context = find_by(target_id: params["targetId"])
        context&.delete_target(params["targetId"])
      end
    end

    def discover
      @client.command("Target.setDiscoverTargets", discover: true)
    end

    def auto_attach
      return unless @client.options.flatten

      @client.command("Target.setAutoAttach", autoAttach: true, waitForDebuggerOnStart: true, flatten: true)
    end
  end
end
