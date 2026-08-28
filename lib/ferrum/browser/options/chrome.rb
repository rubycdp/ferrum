# frozen_string_literal: true

module Ferrum
  class Browser
    class Options
      #
      # Chrome/Chromium-specific default flags and binary locations. Provides
      # the CLI flags required to drive Chrome over CDP as well as the
      # hardened defaults (disabling background networking, extensions,
      # infobars, etc.) applied unless the user opts out.
      #
      class Chrome < Base
        DEFAULT_OPTIONS = {
          "allow-pre-commit-input" => nil,
          "disable-background-networking" => nil,
          "disable-background-timer-throttling" => nil,
          "disable-backgrounding-occluded-windows" => nil,
          "disable-blink-features" => "AutomationControlled",
          "disable-breakpad" => nil,
          "disable-client-side-phishing-detection" => nil,
          "disable-component-extensions-with-background-pages" => nil,
          "disable-component-update" => nil,
          "disable-crash-reporter" => nil,
          "disable-default-apps" => nil,
          "disable-dev-shm-usage" => nil,
          "disable-extensions" => nil,
          "disable-features" => %w[
            site-per-process
            IsolateOrigins
            TranslateUI
            Translate
            MacAppCodeSignClone
            InterestFeedContentSuggestion
            OptimizationHints
            AcceptCHFrame
            MediaRouter
          ].join(","),
          "disable-field-trial-config" => nil,
          "disable-hang-monitor" => nil,
          "disable-infobars" => nil,
          "disable-ipc-flooding-protection" => nil,
          "disable-popup-blocking" => nil,
          "disable-prompt-on-repost" => nil,
          "disable-renderer-backgrounding" => nil,
          "disable-search-engine-choice-screen" => nil,
          "disable-session-crashed-bubble" => nil,
          "disable-site-isolation-trials" => nil,
          "disable-smooth-scrolling" => nil,
          "disable-sync" => nil,
          "disable-translate" => nil,
          "disable-web-security" => nil,
          "enable-automation" => nil,
          "enable-features" => %w[
            NetworkService
            NetworkServiceInProcess
          ].join(","),
          "force-color-profile" => "srgb",
          "headless" => nil,
          "hide-scrollbars" => nil,
          "keep-alive-for-test" => nil,
          "metrics-recording-only" => nil,
          "mute-audio" => nil,
          "no-crash-upload" => nil,
          "no-default-browser-check" => nil,
          "no-first-run" => nil,
          "no-startup-window" => nil,
          "password-store" => "basic",
          "remote-allow-origins" => "*",
          "safebrowsing-disable-auto-update" => nil,
          "use-mock-keychain" => nil
        }.freeze

        MAC_BIN_PATH = [
          "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
          "/Applications/Chromium.app/Contents/MacOS/Chromium"
        ].freeze
        LINUX_BIN_PATH = %w[chrome google-chrome google-chrome-stable google-chrome-beta
                            chromium chromium-browser google-chrome-unstable].freeze
        WINDOWS_BIN_PATH = [
          "C:/Program Files/Google/Chrome/Application/chrome.exe",
          "C:/Program Files/Google/Chrome Dev/Application/chrome.exe"
        ].freeze
        PLATFORM_PATH = {
          mac: MAC_BIN_PATH,
          windows: WINDOWS_BIN_PATH,
          linux: LINUX_BIN_PATH
        }.freeze

        #
        # Merges CLI flags required for Chrome to work with CDP.
        #
        # @param [Hash] flags
        #   Flags to merge required ones into.
        #
        # @param [Ferrum::Browser::Options] options
        #   Browser options.
        #
        # @param [String] user_data_dir
        #   Path to the browser's user data directory.
        #
        # @return [Hash]
        #   Merged flags.
        #
        def merge_required(flags, options, user_data_dir)
          flags = flags.merge("remote-debugging-port" => options.port,
                              "window-size" => options.window_size&.join(","),
                              "user-data-dir" => user_data_dir)

          if options.proxy
            flags.merge!("proxy-server" => "#{options.proxy[:host]}:#{options.proxy[:port]}")
            flags.merge!("proxy-bypass-list" => options.proxy[:bypass]) if options.proxy[:bypass]
          end

          flags
        end

        #
        # Merges Chrome's default flags with the given ones, unless the browser
        # is configured to ignore default browser options.
        #
        # @param [Hash] flags
        #   Flags that take precedence over the defaults.
        #
        # @param [Ferrum::Browser::Options] options
        #   Browser options.
        #
        # @return [Hash]
        #   Merged flags.
        #
        def merge_default(flags, options)
          defaults = options.headless == false ? except("headless", "disable-gpu") : DEFAULT_OPTIONS.dup
          defaults.delete("no-startup-window") if options.incognito == false

          if options.dockerize || ENV["FERRUM_CHROME_DOCKERIZE"] == "true"
            # NOTE: --no-sandbox is not needed if you properly set up a user in the container.
            # https://github.com/ebidel/lighthouse-ci/blob/master/builder/Dockerfile#L35-L40
            defaults = defaults.merge("no-sandbox" => nil, "disable-setuid-sandbox" => nil)
          end

          # On Windows, the --disable-gpu flag is a temporary workaround for a few bugs.
          # See https://bugs.chromium.org/p/chromium/issues/detail?id=737678 for more information.
          defaults = defaults.merge("disable-gpu" => nil) if Utils::Platform.windows?

          # Use Metal on Apple Silicon
          # https://github.com/google/angle#platform-support-via-backing-renderers
          defaults = defaults.merge("use-angle" => "metal") if Utils::Platform.mac_arm?

          defaults.merge(flags)
        end
      end
    end
  end
end
