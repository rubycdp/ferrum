# frozen_string_literal: true

module Ferrum
  class Browser
    class Firefox < Command
      DEFAULT_OPTIONS = {
        "headless" => nil,
      }.freeze

      MAC_BIN_PATH = [
        "/Applications/Firefox.app/Contents/MacOS/firefox-bin"
      ].freeze
      LINUX_BIN_PATH = %w[firefox].freeze

      private

      def combine_required_flags
        port = options.fetch(:port, BROWSER_PORT)
        host = options.fetch(:host, BROWSER_HOST)
        @flags.merge!("remote-debugger" => "#{host}:#{port}")

        @flags.merge!("profile" => @user_data_dir)
      end

      def combine_default_flags
        @flags = DEFAULT_OPTIONS.merge(@flags)

        unless options.fetch(:headless, true)
          @flags.delete("headless")
        end

        @flags.merge!(options.fetch(:browser_options, {}))
      end
    end
  end
end
