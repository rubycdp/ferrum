# frozen_string_literal: true

require "ferrum/target"

module Ferrum
  #
  # Represents a browser context, i.e. an isolated browsing profile (similar
  # to an incognito window) with its own cookies, cache and storage. Keeps
  # track of the {Target}s that belong to it and connects to them as {Page}s
  # or {Worker}s. Managed by {Contexts}, which owns the browser's collection
  # of contexts and routes CDP target events to the right one.
  #
  class Context
    POSITION = %i[first last].freeze

    attr_reader :id, :targets

    def initialize(client, contexts, id, implicit: false)
      @id = id
      @implicit = implicit
      @client = client
      @contexts = contexts
      @targets = Concurrent::Map.new
      @pendings = Concurrent::Map.new
    end

    # Whether this is the browser's implicit context, the one it puts its
    # startup window in. We didn't create it, so we can't dispose it, and
    # Chrome doesn't let us address it by id either: targets are created in
    # it by omitting `browserContextId` altogether.
    #
    # @return [Boolean]
    def implicit?
      @implicit
    end

    # The context's first known target, creating one via
    # `Target.createTarget` if none has attached yet.
    #
    # @return [Target]
    def default_target
      @default_target ||= create_target
    end

    # Connects to and returns the {#default_target}'s page.
    #
    # @return [Page]
    def page
      default_target.page
    end

    # All page targets in this context, connected to as {Page}s.
    #
    # @return [Array<Page>]
    def pages
      @targets.values.select(&:page?).map(&:page)
    end

    # Dedicated and shared workers spawned by any page in this context.
    #
    # @return [Array<Worker>]
    def workers
      @targets.values.select { |t| t.worker? || t.shared_worker? }.map(&:worker)
    end

    # Service worker targets registered in this context. Unlike {#workers},
    # these are plain {Target}s and are not connected to. Attaching to a
    # service worker's session keeps it alive indefinitely, so we only do
    # that on demand, via `target.worker`.
    #
    # @return [Array<Target>]
    def service_workers
      @targets.values.select(&:service_worker?)
    end

    # When we call `page` method on target it triggers ruby to connect to given
    # page by WebSocket, if there are many opened windows, but we need only one
    # it makes more sense to get and connect to the needed one only which
    # usually is the last one.
    def windows(pos = nil, size = 1)
      raise ArgumentError if pos && !POSITION.include?(pos)

      windows = @targets.values.select(&:window?)
      windows = windows.send(pos, size) if pos
      windows.map(&:page)
    end

    # Creates a new target in this context and eagerly connects to it as a
    # {Page}, forwarding `options` to {Target#build_page}.
    #
    # @param [Hash] options
    #
    # @return [Page]
    def create_page(**options)
      target = create_target
      target.page = target.build_page(**options)
    end

    # Creates a new target in this context via `Target.createTarget` and
    # blocks until it's been registered (see {#add_target}).
    #
    # @return [Target]
    #
    # @raise [NoSuchTargetError]
    def create_target
      options = { browserContextId: @id } unless implicit?
      target_id = @client.command("Target.createTarget", url: "about:blank", **Hash(options))["targetId"]

      new_pending = Concurrent::IVar.new
      pending = @pendings.put_if_absent(target_id, new_pending) || new_pending
      resolved = pending.value(@client.protocol_timeout)
      raise NoSuchTargetError unless resolved

      @pendings.delete(target_id)
      @targets[target_id]
    end

    # Registers a target discovered via a CDP `Target.*` event, or updates
    # the session id on one already known. Called by {Contexts} as targets
    # are created/attached.
    #
    # @param [Hash] params
    #   The target's `targetInfo`.
    #
    # @param [String, nil] session_id
    #
    # @return [Target]
    def add_target(params:, session_id: nil)
      new_target = Target.new(@client, session_id, params)
      # `put_if_absent` returns nil if added a new value or existing if there was one already
      target = @targets.put_if_absent(new_target.id, new_target) || new_target
      # on first iteration session_id may be nil, then if session is present here we must set it to the target
      target.session_id = session_id if session_id && target.session_id.nil?
      @default_target ||= target

      new_pending = Concurrent::IVar.new
      pending = @pendings.put_if_absent(target.id, new_pending) || new_pending
      pending.try_set(true)
      target
    end

    # Updates a known target's params, e.g. on `Target.targetInfoChanged`.
    #
    # @param [String] target_id
    #
    # @param [Hash] params
    #
    # @return [void]
    def update_target(target_id, params)
      @targets[target_id]&.update(params)
    end

    # Removes a target, e.g. on `Target.targetDestroyed`/`targetCrashed`.
    #
    # @param [String] target_id
    #
    # @return [Target, nil]
    def delete_target(target_id)
      @targets.delete(target_id)
    end

    # Manually attaches to a target, e.g. a service worker discovered via
    # {#service_workers}. Once attached, `target.worker`/`target.page`
    # returns a connected {Worker}/{Page} for it.
    #
    # Note: attaching to a service worker's session prevents Chrome from
    # ever terminating it while the connection is open.
    def attach_target(target_id)
      target = @targets[target_id]
      raise NoSuchTargetError unless target

      @contexts.manually_attached(target_id)
      session = @client.command("Target.attachToTarget", targetId: target_id, flatten: true)
      target.session_id = session["sessionId"]
      true
    end

    # Returns the first target for which the block returns truthy.
    #
    # @return [Target, nil]
    def find_target
      @targets.each_value { |t| return t if yield(t) }

      nil
    end

    # Closes the WebSocket connection of every connected target, without
    # disposing the targets themselves.
    #
    # @return [void]
    def close_targets_connection
      @targets.each_value do |target|
        next unless target.connected?

        target.close_connection
      end
    end

    # Disposes this browser context and all of its targets. The browser's
    # implicit context cannot be disposed, see {#implicit?}.
    #
    # @return [Boolean, nil]
    def dispose
      @contexts.dispose(@id)
    end

    # Whether a target with the given id is known in this context.
    #
    # @param [String] target_id
    #
    # @return [Boolean]
    def target?(target_id)
      !!@targets[target_id]
    end

    # Debug representation of the context, including its known targets.
    #
    # @return [String]
    def inspect
      %(#<#{self.class} @id=#{@id.inspect} @targets=#{@targets.inspect} @default_target=#{@default_target.inspect}>)
    end
  end
end
