# frozen_string_literal: true

module Ferrum
  class Targets
    TARGETS_RETRY_ATTEMPTS = 3
    TARGETS_RETRY_WAIT = 0.001

    def initialize(browser)
      @page = nil
      @mutex = Mutex.new
      @browser = browser
      @_default = targets.first["targetId"]

      @browser.on("Target.detachedFromTarget") do |params|
        page = remove_page(params["targetId"])
        page&.close_connection
      end

      reset
    end

    def push(target_id, page = nil)
      @targets[target_id] = page
    end

    def refresh
      @mutex.synchronize do
        targets.each { |t| push(t["targetId"]) if !default?(t) && !has?(t) }
      end
    end

    def page
      raise NoSuchWindowError unless @page
      @page
    end

    def window_handle
      page.target_id
    end

    def window_handles
      @mutex.synchronize { @targets.keys }
    end

    def switch_to_window(target_id)
      @page = find_or_create_page(target_id)
    end

    def open_new_window
      target_id = @browser.command("Target.createTarget", url: "about:blank", browserContextId: @_context_id)["targetId"]
      page = Page.new(target_id, @browser, true)
      push(target_id, page)
      target_id
    end

    def close_window(target_id)
      remove_page(target_id)&.close
    end

    def within_window(locator)
      original = window_handle

      if window_handles.include?(locator)
        switch_to_window(locator)
        yield
      else
        raise NoSuchWindowError
      end
    ensure
      switch_to_window(original)
    end

    def reset
      if @page
        @page.close
        @browser.command("Target.disposeBrowserContext", browserContextId: @_context_id)
      end

      @page = nil
      @targets = {}
      @_context_id = nil

      @_context_id = @browser.command("Target.createBrowserContext")["browserContextId"]
      target_id = @browser.command("Target.createTarget", url: "about:blank", browserContextId: @_context_id)["targetId"]
      @page = Page.new(target_id, @browser)
      push(target_id, @page)
    end

    private

    def find_or_create_page(target_id)
      page = @targets[target_id]
      page ||= Page.new(target_id, @browser, true)
      @targets[target_id] ||= page
      page
    end

    def remove_page(target_id)
      page = @targets.delete(target_id)
      @page = nil if page && @page == page
      page
    end

    def targets
      Ferrum.with_attempts(errors: EmptyTargetsError,
                           max: TARGETS_RETRY_ATTEMPTS,
                           wait: TARGETS_RETRY_WAIT) do
        # Targets cannot be empty the must be at least one default target.
        targets = @browser.command("Target.getTargets")["targetInfos"]
        raise EmptyTargetsError if targets.empty?
        targets
      end
    end

    def default?(target)
      @_default == target["targetId"]
    end

    def has?(target)
      @targets.key?(target["targetId"])
    end
  end
end
