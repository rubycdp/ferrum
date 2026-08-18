# frozen_string_literal: true

require "ferrum/context"

module Ferrum
  class Contexts
    ALLOWED_TARGET_TYPES = %w[page iframe worker shared_worker service_worker].freeze
    RECURSIVE_AUTO_ATTACH_TYPES = %w[page iframe worker shared_worker].freeze

    include Enumerable

    attr_reader :contexts

    def initialize(client)
      @client = client
      @contexts = Concurrent::Map.new
      @manually_attached = Concurrent::Map.new
      subscribe
      auto_attach
      discover
    end

    # Marks a target, so the next time we see it attached, we leave its session alone instead of {#detach}ing it.
    # Used by {Context#attach_target} right before it manually attaches to a service worker on the caller's behalf.
    def manually_attached(target_id)
      @manually_attached[target_id] = true
    end

    # The browser's first context, created lazily.
    #
    # @return [Context]
    def default_context
      @default_context ||= create
    end

    # Iterates over `[id, context]` pairs; returns an `Enumerator` if no
    # block is given.
    #
    # @return [void, Enumerator]
    def each(&)
      return enum_for(__method__) unless block_given?

      @contexts.each(&)
    end

    # The context with the given id, if any.
    #
    # @param [String] id
    #
    # @return [Context, nil]
    def [](id)
      @contexts[id]
    end

    # The context that owns the given target, if any.
    #
    # @param [String] target_id
    #
    # @return [Context, nil]
    def find_by(target_id:)
      context = nil
      @contexts.each_value { |c| context = c if c.target?(target_id) }
      context
    end

    # Creates a new browser context (like an incognito profile).
    #
    # @param [Hash] options
    #   Keyword arguments forwarded to `Target.createBrowserContext`.
    #
    # @return [Context]
    def create(**options)
      response = @client.command("Target.createBrowserContext", **options)
      context_id = response["browserContextId"]
      context = Context.new(@client, self, context_id)
      @contexts[context_id] = context
      context
    end

    # Disposes a browser context and all of its targets.
    #
    # @param [String] context_id
    #
    # @return [Boolean]
    def dispose(context_id)
      context = @contexts[context_id]
      return unless context

      context.close_targets_connection
      @client.command("Target.disposeBrowserContext", browserContextId: context.id)
      @contexts.delete(context_id)
      true
    end

    # Closes the WebSocket connection of every target in every context,
    # without disposing the contexts themselves.
    #
    # @return [void]
    def close_connections
      @contexts.each_value(&:close_targets_connection)
    end

    # Disposes every context still known to the browser.
    #
    # @return [void]
    def reset
      context_ids = @client.command("Target.getBrowserContexts")["browserContextIds"]
      @default_context = nil if context_ids.include?(@default_context&.id)
      @contexts.each_key { |id| dispose(id) if context_ids.include?(id) }
    end

    # Number of known contexts.
    #
    # @return [Integer]
    def size
      @contexts.size
    end

    private

    def subscribe
      subscribe_attached_target(@client)
      subscribe_target_created
    end

    # Registered once on the top-level client, and again on every page's/
    # worker's own session once we re-arm auto-attach on it.
    def subscribe_attached_target(client)
      client.on("Target.attachedToTarget") do |params|
        info, session_id = params.values_at("targetInfo", "sessionId")
        next unless ALLOWED_TARGET_TYPES.include?(info["type"])

        context_id = info["browserContextId"]
        add_context(context_id)
        target = @contexts[context_id]&.add_target(session_id: session_id, params: info)

        rearm_auto_attach(session_id, info["type"])
        handle_attach(target, session_id, params)
      end
    end

    def subscribe_target_created
      @client.on("Target.targetCreated") do |params|
        info = params["targetInfo"]
        next unless ALLOWED_TARGET_TYPES.include?(info["type"])

        context_id = info["browserContextId"]
        add_context(context_id)

        if info["type"] == "iframe" &&
           (target = @contexts[context_id]&.find_target { |t| t.connected? && t.page.frame_by(id: info["targetId"]) })
          @contexts[context_id]&.add_target(session_id: target.session_id, params: info)
        else
          @contexts[context_id]&.add_target(params: info)
        end
      end

      @client.on("Target.targetInfoChanged") do |params|
        info = params["targetInfo"]
        next unless ALLOWED_TARGET_TYPES.include?(info["type"])

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

    def rearm_auto_attach(session_id, type)
      return unless RECURSIVE_AUTO_ATTACH_TYPES.include?(type)

      client = @client.session(session_id)
      client.command("Target.setAutoAttach", autoAttach: true, waitForDebuggerOnStart: true, flatten: true, async: true)
      subscribe_attached_target(client)
    end

    def handle_attach(target, session_id, params)
      return unless target

      if target.service_worker?
        detach_unless_manually_attached(target, session_id)
      elsif target.worker? || target.shared_worker?
        connect_worker(target)
      elsif params["waitingForDebugger"]
        resume(session_id)
      end
    end

    # Attaching keeps a service worker alive forever, so unless the caller
    # explicitly asked to connect to it (via Context#attach_target), we
    # just resume it and let go.
    def detach_unless_manually_attached(target, session_id)
      return if @manually_attached.delete(target.id)

      detach(session_id)
    rescue BrowserError
      nil
    end

    # Workers have no events to notify us when they're ready, so we
    # connect right away. Worker#prepare enables the Network domain and
    # only then resumes the debugger itself.
    def connect_worker(target)
      target.worker
    rescue BrowserError
      nil
    end

    def resume(session_id)
      @client.session(session_id).command("Runtime.runIfWaitingForDebugger", async: true)
    end

    def detach(session_id)
      resume(session_id)
      @client.command("Target.detachFromTarget", sessionId: session_id)
    end

    def discover
      @client.command("Target.setDiscoverTargets", discover: true)
    end

    def auto_attach
      @client.command("Target.setAutoAttach", autoAttach: true, waitForDebuggerOnStart: true, flatten: true)
    end

    def add_context(context_id)
      return if @contexts[context_id]

      context = Context.new(@client, self, context_id)
      @contexts[context_id] = context
      @default_context ||= context # rubocop:disable Naming/MemoizedInstanceVariableName
    end
  end
end
