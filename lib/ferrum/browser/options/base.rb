# frozen_string_literal: true

require "singleton"

module Ferrum
  class Browser
    module Options
      class Base
        BROWSER_HOST = "127.0.0.1"
        BROWSER_PORT = "0"

        include Singleton

        def self.options
          instance
        end

        def to_h
          self.class::DEFAULT_OPTIONS
        end

        def except(*keys)
          to_h.reject { |n, _| keys.include?(n) }
        end

        def detect_path
          if Utils::Platform.mac?
            self.class::MAC_BIN_PATH.find { |n| File.exist?(n) }
          elsif Utils::Platform.windows?
            self.class::WINDOWS_BIN_PATH.find { |path| File.exist?(path) }
          else
            self.class::LINUX_BIN_PATH.find do |name|
              path = Cliver.detect(name) and break(path)
            end
          end
        end

        def merge_required(flags, options, user_data_dir)
          raise NotImplementedError
        end

        def merge_default(flags, options)
          raise NotImplementedError
        end
      end
    end
  end
end
