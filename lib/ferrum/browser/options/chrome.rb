# frozen_string_literal: true

module Ferrum
  class Browser
    module Options
      class Chrome < Base
        DEFAULT_OPTIONS = {
          "headless" => true,
          "disable-gpu" => true,
          "hide-scrollbars" => true,
          "mute-audio" => true,
          "enable-automation" => true,
          "disable-web-security" => true,
          "disable-session-crashed-bubble" => true,
          "disable-breakpad" => true,
          "disable-sync" => true,
          "no-first-run" => true,
          "use-mock-keychain" => true,
          "keep-alive-for-test" => true,
          "disable-popup-blocking" => true,
          "disable-extensions" => true,
          "disable-hang-monitor" => true,
          "disable-features" => "site-per-process,TranslateUI",
          "disable-translate" => true,
          "disable-background-networking" => true,
          "enable-features" => "NetworkService,NetworkServiceInProcess",
          "disable-background-timer-throttling" => true,
          "disable-backgrounding-occluded-windows" => true,
          "disable-client-side-phishing-detection" => true,
          "disable-default-apps" => true,
          "disable-dev-shm-usage" => true,
          "disable-ipc-flooding-protection" => true,
          "disable-prompt-on-repost" => true,
          "disable-renderer-backgrounding" => true,
          "force-color-profile" => "srgb",
          "metrics-recording-only" => true,
          "safebrowsing-disable-auto-update" => true,
          "password-store" => "basic",
          "no-startup-window" => true
          # NOTE: --no-sandbox is not needed if you properly setup a user in the container.
          # https://github.com/ebidel/lighthouse-ci/blob/master/builder/Dockerfile#L35-L40
          # "no-sandbox" => true,
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

        def merge_required(flags, options, user_data_dir)
          port = options.fetch(:port, BROWSER_PORT)
          host = options.fetch(:host, BROWSER_HOST)
          flags.merge("remote-debugging-port" => port,
                      "remote-debugging-address" => host,
                      # Doesn't work on MacOS, so we need to set it by CDP
                      "window-size" => options[:window_size]&.join(","),
                      "user-data-dir" => user_data_dir)
        end

        def merge_default(flags, options)
          ensure_required!(
            options,
            %w[remote-debugging-port remote-debugging-address
               window-size user-data-dir]
          )

          defaults = except("headless", "disable-gpu") unless options.fetch(:headless, true)

          defaults ||= DEFAULT_OPTIONS
          defaults.merge(flags)
        end
      end
    end
  end
end
