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
      @client.command("Target.disposeBrowserContext", browserContextId: context.id)
      @contexts.delete(context_id)
      true
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
      @client.on("Target.targetCreated") do |params|
        info = params["targetInfo"]
        next unless info["type"] == "page"

        context_id = info["browserContextId"]
        @contexts[context_id]&.add_target(info)
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
  end
end
