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

    attr_reader :id

    def initialize(client, contexts, id, implicit: false)
      @id = id
      @implicit = implicit
      @client = client
      @contexts = contexts
      @targets = Concurrency::AwaitableMap.new
      @page_waiters = []
      @page_waiters_mutex = Mutex.new
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

    # The cookies of the context, which every page in it shares.
    #
    # @return [Cookies]
    def cookies
      @cookies ||= Cookies.new(@client, @id)
    end

    # Connects to and returns the {#default_target}'s page.
    #
    # @return [Page]
    #
    # @raise [TimeoutError]
    def page
      default_target.page
    end

    # The targets in this context by id, as they are at the time of the call.
    #
    # @return [Hash{String => Target}]
    def targets
      @targets.to_h
    end

    # All page targets in this context, connected to as {Page}s.
    #
    # @yield [target]
    #   Only the pages of the targets the block returns truthy for are
    #   connected to and returned.
    #
    # @yieldparam [Target] target
    #
    # @return [Array<Page>]
    #
    # @raise [TimeoutError]
    #
    # @example The pages opened by another page
    #   browser.pages(&:opener_id)
    def pages(&)
      targets = @targets.values.select(&:page?)
      targets = targets.select(&) if block_given?
      targets.map(&:page)
    end

    # Dedicated and shared workers spawned by any page in this context,
    # leaving out the ones we have no session with, e.g. detached ones.
    #
    # @return [Array<Worker>]
    #
    # @raise [TimeoutError]
    def workers
      @targets.values.select { |t| (t.worker? || t.shared_worker?) && t.session_id }.map(&:worker)
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

    # Runs the block and returns the page it opens, in a tab or a window,
    # e.g. through `window.open` or a link with `target="_blank"`.
    #
    # @param [Page, nil] opener
    #   Only return a page opened by this page. By default a page opened by
    #   any page of the context is returned.
    #
    # @param [Numeric, Deadline] timeout
    #   How long the block and the new page may take together. Defaults to
    #   the browser's `timeout`.
    #
    # @yield The code that opens the page.
    #
    # @return [Page, nil]
    #   The first page opened since the call, `nil` if none opens in time.
    #
    # @example
    #   opened = browser.wait_for_new_page { browser.at_css("a[target=_blank]").click }
    #   opened.url # => "https://example.com/"
    def wait_for_new_page(opener: nil, timeout: @client.timeout)
      deadline = Deadline.wrap(timeout)
      waiter = [opener&.target_id, Concurrency::Cell.new]
      @page_waiters_mutex.synchronize { @page_waiters << waiter }
      yield if block_given?
      return unless waiter.last.wait(deadline)

      waiter.last.value.page
    ensure
      @page_waiters_mutex.synchronize { @page_waiters.delete(waiter) }
    end

    # Same as {#wait_for_new_page}, but raises if no page opens in time.
    #
    # @param [Hash] options
    #   The options of {#wait_for_new_page}.
    #
    # @yield The code that opens the page.
    #
    # @return [Page]
    #
    # @raise [TimeoutError]
    #   If no page opens in time.
    def wait_for_new_page!(**options, &)
      wait_for_new_page(**options, &) || raise(TimeoutError)
    end

    # Creates a new target in this context and eagerly connects to it as a
    # {Page}, forwarding `options` to {Target#build_page}.
    #
    # @param [Hash] options
    #
    # @return [Page]
    #
    # @raise [TimeoutError]
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
    #
    # @raise [TimeoutError]
    def create_target
      options = { browserContextId: @id } unless implicit?
      deadline = Deadline.wrap(@client.timeout)
      response = @client.command("Target.createTarget", timeout: deadline, url: "about:blank", **Hash(options))
      @targets.await(response["targetId"], deadline) || raise(NoSuchTargetError)
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
    # @param [Boolean] attached
    #   The session comes from `Target.attachedToTarget`, so it replaces the one a target got from its frame owner.
    #
    # @return [Target]
    def add_target(params:, session_id: nil, attached: false)
      new_target = Target.new(@client, session_id, params, implicit: implicit?)
      target = @targets[new_target.id] || new_target
      # on first iteration session_id may be nil, then if session is present here we must set it to the target
      target.session_id = session_id if session_id && (attached || target.session_id.nil?)
      @default_target ||= target
      @targets[target.id] = target
      announce_page(target) if target.equal?(new_target)
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
    # returns a connected {Worker}/{Page} for it. A target that already has
    # a session keeps it.
    #
    # Note: attaching to a service worker's session prevents Chrome from
    # ever terminating it while the connection is open.
    #
    # @param [String] target_id
    #
    # @return [Target]
    #
    # @raise [NoSuchTargetError] if the context has no such target.
    #
    # @raise [TimeoutError]
    def attach_target(target_id)
      target = @targets[target_id]
      raise NoSuchTargetError unless target
      return target if target.session_id

      @contexts.manually_attached(target_id)
      session = @client.command("Target.attachToTarget", timeout: Client::PROTOCOL_TIMEOUT,
                                                         targetId: target_id, flatten: true)
      target.session_id = session["sessionId"]
      target
    end

    # Returns the first target for which the block returns truthy.
    #
    # @return [Target, nil]
    def find_target
      targets = @targets.values
      targets.each { |t| return t if yield(t) }

      nil
    end

    # Closes the WebSocket connection of every connected target, without
    # disposing the targets themselves.
    #
    # @return [void]
    def close_targets_connection
      @targets.values.select(&:connected?).each(&:close_connection)
    end

    # Disposes this browser context and all of its targets. The browser's
    # implicit context cannot be disposed, see {#implicit?}.
    #
    # @return [Boolean, nil]
    #
    # @raise [TimeoutError]
    def dispose
      @contexts.dispose(@id)
    end

    # The target with the given id.
    #
    # @param [String] target_id
    #
    # @return [Target, nil]
    #   `nil` when the context has no such target.
    def target(target_id)
      @targets[target_id]
    end

    # Whether a target with the given id is known in this context.
    #
    # @param [String] target_id
    #
    # @return [Boolean]
    def target?(target_id)
      !!target(target_id)
    end

    # Debug representation of the context, including its known targets.
    #
    # @return [String]
    def inspect
      %(#<#{self.class} @id=#{@id.inspect} @targets=#{@targets.inspect} @default_target=#{@default_target.inspect}>)
    end

    private

    def announce_page(target)
      return unless target.page? && target.opener_id

      waiters = @page_waiters_mutex.synchronize { @page_waiters.select { |id, _| id.nil? || id == target.opener_id } }
      waiters.each { |w| w.last.set(target) }
    end
  end
end
