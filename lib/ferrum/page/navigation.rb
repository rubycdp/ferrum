# frozen_string_literal: true

module Ferrum
  class Page
    #
    # Navigation of the page's main frame: {#go_to}, {#refresh}, the history
    # and {#await_navigation} for a navigation that other code starts.
    #
    module Navigation
      #
      # Navigates the page to a URL and waits for it to load.
      #
      # @param [String, nil] url
      #   The URL to navigate to. The url should include scheme unless you set
      #   `{Browser#base_url = url}` when configuring.
      #
      # @param [Numeric, Deadline, nil] timeout
      #   How long the whole navigation may take, from sending the request to the
      #   page loading. Defaults to the page's `timeout`.
      #
      # @param [String, nil] referrer
      #   The referrer of this navigation only, what the document request sends
      #   as `Referer` and `document.referrer` returns. A `Referer` header set
      #   with {Headers#add} or {Headers#set} is sent with every request and
      #   takes its place.
      #
      # @return [String, nil]
      #   The navigated frame's id, or `nil` when the page doesn't load in time.
      #
      # @raise [StatusError]
      #   If the request fails.
      #
      # @raise [NavigationTimeoutError]
      #   Once the budget of an enclosing {Deadline.within} is used up.
      #
      # @example
      #   page.go_to("https://github.com/")
      #   page.go_to("/slow", timeout: 10)
      #   page.go_to("/landing", referrer: "https://google.com")
      #
      def go_to(url = nil, timeout: nil, referrer: nil)
        go_to!(url, timeout: timeout, referrer: referrer)
      rescue NavigationTimeoutError
        raise if Deadline.current&.expired?

        nil
      end

      #
      # @deprecated Will be removed in Ferrum 0.22. Use {#go_to}.
      #
      # @param [String, nil] url
      #
      # @param [Hash{Symbol => Object}] options
      #   Passed to {#go_to}.
      #
      # @return [String, nil]
      #
      def goto(url = nil, **options)
        Utils::Deprecate.warn("goto will be removed in Ferrum 0.22. Use go_to instead.", user_code: true)
        go_to(url, **options)
      end

      #
      # @deprecated Will be removed in Ferrum 0.22. Use {#go_to}.
      #
      # @param [String, nil] url
      #
      # @param [Hash{Symbol => Object}] options
      #   Passed to {#go_to}.
      #
      # @return [String, nil]
      #
      def go(url = nil, **options)
        Utils::Deprecate.warn("go will be removed in Ferrum 0.22. Use go_to instead.", user_code: true)
        go_to(url, **options)
      end

      #
      # Same as {#go_to}, but raises if the page doesn't load in time.
      #
      # @param [String, nil] url
      #
      # @param [Numeric, Deadline, nil] timeout
      #
      # @param [String, nil] referrer
      #
      # @return [String]
      #   The navigated frame's id.
      #
      # @raise [StatusError]
      #   If the request fails.
      #
      # @raise [NavigationTimeoutError]
      #   If the page doesn't load in time, naming the requests still pending.
      #
      # @example
      #   page.go_to!("/slow", timeout: 10)
      #
      def go_to!(url = nil, timeout: nil, referrer: nil)
        options = { url: combine_url!(url) }
        referrer ||= headers.get["Referer"]
        options.merge!(referrer: referrer) if referrer
        deadline = Deadline.wrap(timeout || self.timeout)
        response = nil
        navigate!(options[:url], deadline) do
          response = command("Page.navigate", timeout: deadline, **options)
        end
        error_text = response["errorText"] # https://cs.chromium.org/chromium/src/net/base/net_error_list.h
        if error_text && error_text != "net::ERR_ABORTED" # Request aborted due to user action or download
          raise StatusError.new(options[:url], "Request to #{options[:url]} failed (#{error_text})")
        end

        response["frameId"]
      end

      #
      # Reloads the current page and waits for it to load.
      #
      # @param [Numeric, Deadline, nil] timeout
      #   How long the whole reload may take. Defaults to the page's `timeout`.
      #
      # @return [true, nil]
      #   `nil` when the page doesn't load in time.
      #
      # @example
      #   page.go_to("https://github.com/")
      #   page.refresh # => true
      #
      def refresh(timeout: nil)
        nil_on_timeout { refresh!(timeout: timeout) }
      end

      #
      # @deprecated Will be removed in Ferrum 0.22. Use {#refresh}.
      #
      # @param [Numeric, Deadline, nil] timeout
      #
      # @return [true, nil]
      #
      def reload(timeout: nil)
        Utils::Deprecate.warn("reload will be removed in Ferrum 0.22. Use refresh instead.", user_code: true)
        refresh(timeout: timeout)
      end

      #
      # Same as {#refresh}, but raises if the page doesn't load in time.
      #
      # @param [Numeric, Deadline, nil] timeout
      #
      # @return [true]
      #
      # @raise [NavigationTimeoutError]
      #
      def refresh!(timeout: nil)
        deadline = Deadline.wrap(timeout || self.timeout)
        navigate!(nil, deadline) { command("Page.reload", timeout: deadline, slowmoable: true) }
        true
      end

      #
      # @deprecated Will be removed in Ferrum 0.22. Use {#refresh!}.
      #
      # @param [Numeric, Deadline, nil] timeout
      #
      # @return [true]
      #
      # @raise [NavigationTimeoutError]
      #
      def reload!(timeout: nil)
        Utils::Deprecate.warn("reload! will be removed in Ferrum 0.22. Use refresh! instead.", user_code: true)
        refresh!(timeout: timeout)
      end

      #
      # Stop all navigations and loading pending resources on the page.
      #
      # @return [nil]
      #
      # @raise [TimeoutError]
      #
      # @example
      #   page.go_to("https://github.com/")
      #   page.stop
      #
      def stop
        command("Page.stopLoading", slowmoable: true)
        nil
      end

      #
      # Navigates to the previous URL in the history and waits for it to load.
      #
      # @param [Numeric, Deadline, nil] timeout
      #   How long the history lookup and the page load may take together, the page timeout by default.
      #
      # @return [true, nil]
      #   `nil` when there's no previous URL or the page doesn't load in time.
      #
      # @example
      #   page.go_to("https://github.com/")
      #   page.at_xpath("//a").click
      #   page.back
      #
      def back(timeout: nil)
        nil_on_timeout { back!(timeout: timeout) }
      end

      #
      # Same as {#back}, but raises if the page doesn't load in time.
      #
      # @param [Numeric, Deadline, nil] timeout
      #
      # @return [true, nil]
      #   `nil` when there's no previous URL.
      #
      # @raise [NavigationTimeoutError]
      #
      def back!(timeout: nil)
        history_navigate(delta: -1, timeout: timeout)
      end

      #
      # Navigates to the next URL in the history and waits for it to load.
      #
      # @param [Numeric, Deadline, nil] timeout
      #   How long the history lookup and the page load may take together, the page timeout by default.
      #
      # @return [true, nil]
      #   `nil` when there's no next URL or the page doesn't load in time.
      #
      # @example
      #   page.go_to("https://github.com/")
      #   page.at_xpath("//a").click
      #   page.back
      #   page.forward
      #
      def forward(timeout: nil)
        nil_on_timeout { forward!(timeout: timeout) }
      end

      #
      # Same as {#forward}, but raises if the page doesn't load in time.
      #
      # @param [Numeric, Deadline, nil] timeout
      #
      # @return [true, nil]
      #   `nil` when there's no next URL.
      #
      # @raise [NavigationTimeoutError]
      #
      def forward!(timeout: nil)
        history_navigate(delta: 1, timeout: timeout)
      end

      #
      # Runs the block and waits for the navigation of the main frame it starts
      # to finish, e.g. after a click on a link made from JavaScript.
      #
      # @param [Numeric, nil] watch
      #   Seconds to watch for a navigation after the block returns, for code
      #   that may or may not navigate. When none begins in that time it
      #   returns `true` right away. By default a navigation must happen within
      #   `timeout`.
      #
      # @param [Numeric, Deadline, nil] timeout
      #   How long the block and the navigation it starts may take together.
      #   Defaults to the page's `timeout`.
      #
      # @yield The code that starts the navigation.
      #
      # @return [true, nil]
      #   `nil` when the page doesn't load in time.
      #
      # @raise [ArgumentError]
      #   If no block is given.
      #
      # @example
      #   page.await_navigation { page.at_css("a").evaluate("this.click()") } # => true
      #   page.await_navigation(watch: 0.1) { page.at_css("button").evaluate("this.click()") } # => true
      #
      def await_navigation(watch: nil, timeout: nil)
        raise ArgumentError, "await_navigation needs a block that starts the navigation" unless block_given?

        deadline = Deadline.wrap(timeout || self.timeout)
        was_idle = @idle.set?
        generation = @idle.clear
        yield
        if watch
          @idle.wait([watch, deadline.remaining].min)
          if generation == @idle.generation
            @idle.set(true) if was_idle
            return true
          end
        end
        loaded = @idle.wait(deadline)
        @idle.set(true) if !loaded && was_idle && generation == @idle.generation
        loaded || nil
      end

      #
      # Same as {#await_navigation}, but raises if the page doesn't load in time.
      #
      # @param [Numeric, nil] watch
      #
      # @param [Numeric, Deadline, nil] timeout
      #
      # @yield The code that starts the navigation.
      #
      # @return [true]
      #
      # @raise [TimeoutError]
      #   If the page doesn't load in time.
      #
      # @raise [ArgumentError]
      #   If no block is given.
      #
      def await_navigation!(watch: nil, timeout: nil, &block)
        await_navigation(watch: watch, timeout: timeout, &block) || raise(TimeoutError)
      end

      #
      # Blocks until the page reloads or the timeout is reached.
      #
      # @deprecated Will be removed in Ferrum 0.22. Use {#await_navigation} around the code that reloads the page.
      #
      # @param [Numeric, Deadline] timeout
      #   Maximum time in seconds to wait for a reload event.
      #
      # @return [void]
      #
      # @example
      #   page.wait_for_reload
      #
      def wait_for_reload(timeout = 1)
        Utils::Deprecate.warn(WAIT_FOR_RELOAD_DEPRECATED, user_code: true)
        deadline = Deadline.wrap(timeout)
        generation = @idle.clear if @idle.set?
        @idle.wait(deadline)
        @idle.set(true) if generation == @idle.generation
      end

      #
      # Runs the block and, if it starts a navigation within `navigation_wait`
      # seconds, waits for that navigation to finish.
      #
      # @deprecated Will be removed in Ferrum 0.22. Use {#await_navigation} with `watch:`.
      #
      # @param [Numeric] navigation_wait
      #
      # @param [Numeric, Deadline, nil] timeout
      #
      # @yield The code that may start a navigation.
      #
      # @return [Boolean]
      #
      def wait_for_navigation(navigation_wait = NAVIGATION_WAIT, timeout: nil, &)
        Utils::Deprecate.warn(WAIT_FOR_NAVIGATION_DEPRECATED, user_code: true)
        await_navigation(watch: navigation_wait, timeout: timeout, &) || false
      end

      #
      # Same as {#wait_for_navigation}, but raises if the page doesn't load in time.
      #
      # @deprecated Will be removed in Ferrum 0.22. Use {#await_navigation!} with `watch:`.
      #
      # @param [Numeric] navigation_wait
      #
      # @param [Numeric, Deadline, nil] timeout
      #
      # @yield The code that may start a navigation.
      #
      # @return [void]
      #
      # @raise [TimeoutError]
      #
      def wait_for_navigation!(navigation_wait = NAVIGATION_WAIT, timeout: nil, &)
        Utils::Deprecate.warn(WAIT_FOR_NAVIGATION_DEPRECATED, user_code: true)
        await_navigation!(watch: navigation_wait, timeout: timeout, &)
        nil
      end

      private

      def history_navigate(delta:, timeout: nil)
        deadline = Deadline.wrap(timeout || self.timeout)
        history = command("Page.getNavigationHistory", timeout: deadline)
        index, entries = history.values_at("currentIndex", "entries")
        return if (index + delta).negative?

        entry = entries[index + delta]
        return unless entry

        navigate!(entry["url"], deadline) do
          command("Page.navigateToHistoryEntry", timeout: deadline, slowmoable: true, entryId: entry["id"])
        end
        true
      end

      def navigate!(url, deadline, &)
        await_navigation!(watch: NAVIGATION_WAIT, timeout: deadline, &)
      rescue TimeoutError
        raise NavigationTimeoutError.new(url, network.traffic.select(&:pending?).map(&:url).compact)
      end

      def nil_on_timeout
        yield
      rescue TimeoutError
        raise if Deadline.current&.expired?

        nil
      end

      def combine_url!(url_or_path)
        url = Addressable::URI.parse(url_or_path)
        nil_or_relative = url.nil? || url.relative?

        if nil_or_relative && !@options.base_url
          raise "Set :base_url browser's option or use absolute url in `go_to`, you passed: #{url_or_path}"
        end

        (nil_or_relative ? @options.base_url.join(url.to_s) : url).to_s
      end
    end
  end
end
