# frozen_string_literal: true

module Ferrum
  class Browser
    class Options
      class Firefox < Base
        DEFAULT_OPTIONS = {
          "headless" => nil
        }.freeze

        MAC_BIN_PATH = [
          "/Applications/Firefox.app/Contents/MacOS/firefox-bin"
        ].freeze
        LINUX_BIN_PATH = %w[firefox].freeze
        WINDOWS_BIN_PATH = [
          "C:/Program Files/Firefox Developer Edition/firefox.exe",
          "C:/Program Files/Mozilla Firefox/firefox.exe"
        ].freeze
        PLATFORM_PATH = {
          mac: MAC_BIN_PATH,
          windows: WINDOWS_BIN_PATH,
          linux: LINUX_BIN_PATH
        }.freeze

        #
        # Merges CLI flags required for Firefox to work with CDP.
        #
        # @param [Hash] flags
        #   Flags to merge required ones into.
        #
        # @param [Ferrum::Browser::Options] options
        #   Browser options.
        #
        # @param [String] user_data_dir
        #   Path to the browser's profile directory.
        #
        # @return [Hash]
        #   Merged flags.
        #
        def merge_required(flags, options, user_data_dir)
          flags.merge("remote-debugger" => "#{options.host}:#{options.port}", "profile" => user_data_dir)
        end

        #
        # Merges Firefox's default flags with the given ones.
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
          defaults = except("headless") unless options.headless

          defaults ||= DEFAULT_OPTIONS
          defaults.merge(flags)
        end
      end
    end
  end
end
