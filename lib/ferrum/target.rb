# frozen_string_literal: true

module Ferrum
  #
  # Represents a CDP target, e.g. a page, iframe, dedicated/shared worker or
  # service worker. Wraps the raw `targetInfo` params and lazily connects to
  # the target as a {Page} or {Worker} over its own {Client}/{SessionClient}
  # session, so a `Target` can exist without being connected to yet.
  #
  class Target
    NEW_WINDOW_WAIT = ENV.fetch("FERRUM_NEW_WINDOW_WAIT", 0.3).to_f

    attr_reader :options

    # @note The writer is a private API, Ferrum sets it.
    attr_reader :session_id

    # @api private
    attr_writer :session_id

    # You can create page yourself and assign it to target, used in cuprite
    # where we enhance page class and build page ourselves.
    #
    # @api private
    attr_writer :page

    def initialize(browser_client, session_id = nil, params = nil, implicit: false)
      @page = nil
      @worker = nil
      @session_id = session_id
      @params = params
      @implicit = implicit
      @browser_client = browser_client
      @options = browser_client.options
    end

    # Merges freshly received CDP target info into this target's params,
    # e.g. on `Target.targetInfoChanged`.
    #
    # @param [Hash] params
    #
    # @return [Hash]
    #
    # @api private
    def update(params)
      @params.merge!(params)
    end

    # Whether this target has already been connected to as a {Page} or
    # {Worker}.
    #
    # @return [Boolean]
    def connected?
      !!@page || !!@worker
    end

    # Connects to and returns this target's {Page}.
    #
    # @return [Page]
    #
    # @raise [TimeoutError]
    #
    # @note The writer is a private API, Ferrum sets it.
    def page
      @page ||= build_page
    end

    # Connects to and returns this target's {Worker}.
    #
    # @return [Worker]
    #
    # @raise [NoSuchTargetError] if there's no session with the target, e.g. a service worker
    #   not attached to with {Context#attach_target}.
    #
    # @raise [TimeoutError]
    def worker
      @worker ||= build_worker
    end

    # The client connected to this target's own session.
    #
    # @return [SessionClient]
    def client
      @client ||= build_client
    end

    # Builds a {Page} for this target. Called lazily by `page`, or eagerly
    # by {Context#create_page}.
    #
    # @param [Hash] options
    #
    # @return [Page]
    #
    # @api private
    def build_page(**options)
      maybe_sleep_if_new_window
      Page.new(client, context_id: context_id, target_id: id, **options)
    end

    # Builds a {Worker} for this target. Called lazily by {#worker}.
    #
    # @return [Worker]
    #
    # @api private
    def build_worker
      if session_id.nil?
        raise NoSuchTargetError, "No session with #{type} #{id}, attach to it with Context#attach_target first"
      end

      Worker.new(client, target_id: id, url: url, type: type)
    end

    # Closes the WebSocket connection, without closing the target itself
    # in the browser.
    #
    # @return [void]
    def close_connection
      @page&.close_connection
      @worker&.close_connection
    end

    # The target's id.
    #
    # @return [String]
    def id
      @params["targetId"]
    end

    # The target's type, e.g. `"page"`, `"iframe"`, `"worker"`,
    # `"shared_worker"`, `"service_worker"`.
    #
    # @return [String]
    def type
      @params["type"]
    end

    # The target's title.
    #
    # @return [String]
    def title
      @params["title"]
    end

    # The target's URL.
    #
    # @return [String]
    def url
      @params["url"]
    end

    # The id of the target that opened this one, set only for
    # windows/tabs opened via `window.open`/links/etc.
    #
    # @return [String, nil]
    def opener_id
      @params["openerId"]
    end

    # The id of the target that spawned this one, set for iframes and
    # workers. Unlike `opener_id`, which is only set for windows/tabs opened
    # via `window.open`/links/etc.
    def parent_id
      @params["parentId"]
    end

    # The id of the browser context this target belongs to, `nil` for the
    # browser's implicit context, which Chrome doesn't let us address by id,
    # see {Context#implicit?}. Commands scoped to a browser context target it
    # by omitting `browserContextId`.
    #
    # @return [String, nil]
    def context_id
      @params["browserContextId"] unless @implicit
    end

    # Whether this target is an iframe.
    #
    # @return [Boolean]
    def iframe?
      type == "iframe"
    end

    # Whether this target is a page.
    #
    # @return [Boolean]
    def page?
      type == "page"
    end

    # Whether this target is a dedicated worker.
    #
    # @return [Boolean]
    def worker?
      type == "worker"
    end

    # Whether this target is a shared worker.
    #
    # @return [Boolean]
    def shared_worker?
      type == "shared_worker"
    end

    # Whether this target is a service worker.
    #
    # @return [Boolean]
    def service_worker?
      type == "service_worker"
    end

    # Chrome fires no events for a newly opened window, so we sleep a bit
    # to give it a chance to load before connecting.
    #
    # @return [void]
    #
    # @api private
    def maybe_sleep_if_new_window
      # Dirty hack because new window doesn't have events at all
      sleep(NEW_WINDOW_WAIT) if opener_id
    end

    # Sends a CDP command through {#client}.
    #
    # @param [String] method
    #   The CDP method name.
    #
    # @param [Numeric, Deadline, nil] timeout
    #   How long to wait for the response, the browser's `timeout` by default.
    #
    # @param [Hash] params
    #   The command's parameters.
    #
    # @return [Hash]
    #   The command's result.
    #
    # @raise [TimeoutError]
    #
    # @api private
    def command(method, timeout: nil, **params)
      client.command(method, timeout: timeout || client.timeout, **params)
    end

    private

    def build_client
      @browser_client.session(session_id)
    end
  end
end
