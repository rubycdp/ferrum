# frozen_string_literal: true

module Ferrum
  class Browser
    #
    # Builds the OS-level command used to spawn the browser process: resolves
    # the executable path and merges the browser-specific required/default
    # flags (see {Options::Chrome}) with any user-supplied ones into a single
    # argument list.
    #
    class Command
      NOT_FOUND = "Could not find an executable for the browser. Try to make " \
                  "it available on the PATH or set environment variable for " \
                  "example BROWSER_PATH=\"/usr/bin/chrome\""

      def self.build(options, user_data_dir)
        new(Options::Chrome.options, options, user_data_dir)
      end

      attr_reader :defaults, :path, :options

      def initialize(defaults, options, user_data_dir)
        @flags = {}
        @defaults = defaults
        @options = options
        @user_data_dir = user_data_dir
        @path = options.browser_path || ENV.fetch("BROWSER_PATH", nil) || defaults.detect_path
        raise BinaryNotFoundError, NOT_FOUND unless @path

        merge_options
      end

      # Whether the browser should be launched under Xvfb.
      #
      # @return [Boolean]
      def xvfb?
        !!options.xvfb
      end

      #
      # Command line arguments for spawning the browser process.
      #
      # @return [Array<String>]
      #   The browser path followed by its CLI flags.
      #
      def to_a
        [path] + @flags.map { |k, v| v.nil? ? "--#{k}" : "--#{k}=#{v}" }
      end

      #
      # String representation of the command used to spawn the browser process.
      #
      # @return [String]
      #
      def to_s
        to_a.join(" \\ \n  ")
      end

      private

      def merge_options
        @flags = defaults.merge_required(@flags, options, @user_data_dir)
        @flags = defaults.merge_default(@flags, options) unless options.ignore_default_browser_options
        @flags.merge!(options.browser_options)
      end
    end
  end
end
