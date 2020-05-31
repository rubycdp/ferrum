# frozen_string_literal: true

module Ferrum
  class Browser
    class Command
      BROWSER_HOST = "127.0.0.1"
      BROWSER_PORT = "0"
      NOT_FOUND = "Could not find an executable for the browser. Try to make " \
                  "it available on the PATH or set environment varible for " \
                  "example BROWSER_PATH=\"/usr/bin/chrome\"".freeze

      # Currently only these browsers support CDP:
      # https://github.com/cyrus-and/chrome-remote-interface#implementations
      def self.build(options, user_data_dir)
        case options[:browser_name]
        when :firefox
          Firefox
        when :chrome, :opera, :edge, nil
          Chrome
        else
          raise NotImplementedError, "not supported browser"
        end.new(options, user_data_dir)
      end

      attr_reader :path, :flags, :options

      def initialize(options, user_data_dir)
        @flags = {}
        @options, @user_data_dir = options, user_data_dir
        @path = options[:browser_path] || ENV["BROWSER_PATH"] || detect_path
        raise Cliver::Dependency::NotFound.new(NOT_FOUND) unless @path

        combine_flags
      end

      def xvfb?
        !!@options[:xvfb]
      end

      def to_a
        [path] + flags.map { |k, v| v.nil? ? "--#{k}" : "--#{k}=#{v}" }
      end

      private

      def detect_path
        if Ferrum.mac?
          self.class::MAC_BIN_PATH.find { |b| File.exist?(b) }
        else
          self.class::LINUX_BIN_PATH
            .find { |b| p = Cliver.detect(b) and break(p) }
        end
      end

      def combine_flags
        raise NotImplementedError
      end
    end
  end
end
