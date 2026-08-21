# frozen_string_literal: true

require "singleton"
require "open3"

module Ferrum
  class Browser
    class Options
      #
      # Abstract base for browser-specific default option builders. Subclasses
      # (e.g. {Options::Chrome}, {Options::Firefox}) declare their own
      # `DEFAULT_OPTIONS` and `PLATFORM_PATH` constants and implement
      # {#merge_required}/{#merge_default} to produce the final CLI flags used
      # by {Command}.
      #
      class Base
        include Singleton

        #
        # Singleton instance holding the browser's default options.
        #
        # @return [Base]
        #
        def self.options
          instance
        end

        # The installed browser's version string, obtained by running its
        # binary with `--version`.
        #
        # @return [String, nil]
        #   The version output, or `nil` if the binary can't be found/run.
        def self.version
          out, = Open3.capture2(instance.detect_path, "--version")
          out.strip
        rescue Errno::ENOENT
          nil
        end

        #
        # Default CLI flags for the browser.
        #
        # @return [Hash{String => Object}]
        #
        def to_h
          self.class::DEFAULT_OPTIONS
        end

        #
        # Default CLI flags excluding the given keys.
        #
        # @param [Array<String>] keys
        #   Flag names to exclude.
        #
        # @return [Hash{String => Object}]
        #
        def except(*keys)
          to_h.except(*keys)
        end

        #
        # Locates the browser executable on the system.
        #
        # @return [String, nil]
        #   Absolute path to the browser binary, or `nil` if not found.
        #
        def detect_path
          Binary.find(self.class::PLATFORM_PATH[Utils::Platform.platform_name])
        end

        #
        # Merges the CLI flags that are always required to drive the browser
        # over CDP (e.g. remote debugging port, user data dir) into `flags`.
        # Abstract; overridden by {Options::Chrome}/{Options::Firefox}.
        #
        # @param [Hash{String => Object}] flags
        #   The flags accumulated so far.
        # @param [Options] options
        #   The user-supplied browser options.
        # @param [String] user_data_dir
        #   Path to the browser's user data directory.
        #
        # @return [Hash{String => Object}]
        #
        # @raise [NotImplementedError]
        #   Always, unless overridden by a subclass.
        #
        def merge_required(flags, options, user_data_dir)
          raise NotImplementedError
        end

        #
        # Merges this browser's default CLI flags (see {#to_h}) into `flags`,
        # unless `options.ignore_default_browser_options` is set. Abstract;
        # overridden by {Options::Chrome}/{Options::Firefox}.
        #
        # @param [Hash{String => Object}] flags
        #   The flags accumulated so far.
        # @param [Options] options
        #   The user-supplied browser options.
        #
        # @return [Hash{String => Object}]
        #
        # @raise [NotImplementedError]
        #   Always, unless overridden by a subclass.
        #
        def merge_default(flags, options)
          raise NotImplementedError
        end
      end
    end
  end
end
