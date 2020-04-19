# frozen_string_literal: true

module Ferrum
  class Browser
    module Options
      class Firefox < Base
        DEFAULT_OPTIONS = {
          "headless" => nil,
        }.freeze

        MAC_BIN_PATH = [
          "/Applications/Firefox.app/Contents/MacOS/firefox-bin"
        ].freeze
        LINUX_BIN_PATH = %w[firefox].freeze

        def merge_required(flags, options, user_data_dir)
          port = options.fetch(:port, BROWSER_PORT)
          host = options.fetch(:host, BROWSER_HOST)
          flags.merge("remote-debugger" => "#{host}:#{port}",
                      "profile" => user_data_dir)
        end

        def merge_default(flags, options)
          unless options.fetch(:headless, true)
            defaults = except("headless")
          end

          defaults ||= DEFAULT_OPTIONS
          defaults.merge(flags)
        end
      end
    end
  end
end
