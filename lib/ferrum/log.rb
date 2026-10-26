# frozen_string_literal: true

require "ferrum/log/paint"
require "ferrum/log/default"
require "ferrum/log/json"
require "ferrum/log/annotated"

module Ferrum
  #
  # Writes Ferrum's debug output to the `:logger` given to {Browser.new}, split
  # into channels: `:protocol` (CDP messages) and `:browser` (the output of the
  # Chrome process Ferrum launched).
  #
  # The logger can be an IO-like object responding to `puts`, or a `Logger`,
  # which gets every line at debug level with `ferrum:<channel>` as program
  # name. Nothing is built for a disabled channel or a level the `Logger` skips.
  #
  # `FERRUM_LOG` picks what is written, see {.parse}. `FERRUM_LOG_FORMAT` picks
  # how CDP messages look: `json` writes them as JSON alone, see {Json}, and
  # `annotated` puts the command id and method in front of each message and
  # its response, see {Annotated}. Without it they look as they always have,
  # see {Default}.
  #
  # Written to a terminal, lines are colored with the basic ANSI colors, which
  # terminal themes adapt to light and dark backgrounds. Files, pipes and
  # `Logger`s get plain text, and so does a terminal when `NO_COLOR` is set.
  # `FERRUM_LOG_COLOR=always` or `never` overrides both.
  #
  # Logging never breaks the browser: an error while formatting or writing a
  # line, e.g. a closed IO, is reported once and the line skipped.
  #
  class Log
    include Paint

    CHANNELS = %i[protocol browser].freeze
    ALL = %w[* 1 true].freeze
    OFF = %w[0 false].freeze
    FORMATS = { default: Default, json: Json, annotated: Annotated }.freeze
    VALUE_LENGTH = Integer(ENV.fetch("FERRUM_LOG_VALUE_LENGTH", 1024))

    attr_reader :logger, :channels, :only, :skip

    # Parses `FERRUM_LOG`, a comma-separated list of:
    #
    # * `*`, `1` or `true` - all channels
    # * `protocol`, `browser` - that channel, `-browser` leaves it out
    # * `Page.*`, `Runtime.evaluate` - only CDP messages whose method matches,
    #   which turns `protocol` on
    # * `-Network.*` - leaves out CDP messages whose method matches
    #
    # Without a channel or CDP pattern to log, all channels are logged, so
    # `-browser` means everything but the browser output. Exclusions win over
    # inclusions, and responses follow the command they answer. `0`, `false`
    # or an empty value turn logging off.
    #
    # @param [String, nil] value
    #
    # @return [Hash{Symbol => Array}, nil]
    #   The `channels:`, `only:` and `skip:` for {#initialize}, `nil` when off.
    def self.parse(value)
      items = value.to_s.split(",").map(&:strip).reject(&:empty?)
      return if items.all? { |item| OFF.include?(item) }

      patterns, names = items.partition { |item| item.include?(".") }
      skip, only = patterns.partition { |pattern| pattern.start_with?("-") }
      removed, added = names.partition { |name| name.start_with?("-") }

      channels = added.flat_map { |name| parse_channel(name) }
      channels << :protocol if only.any?
      channels = CHANNELS if channels.empty?
      channels -= removed.flat_map { |name| parse_channel(name.delete_prefix("-")) }

      { channels: channels.uniq, only: only, skip: skip.map { |pattern| pattern.delete_prefix("-") } }
    end

    # Parses one channel item of `FERRUM_LOG`, warning about an unknown one.
    #
    # @param [String] name
    #
    # @return [Array<Symbol>]
    def self.parse_channel(name)
      return CHANNELS if ALL.include?(name)
      return [name.to_sym] if CHANNELS.include?(name.to_sym)

      warn "Ferrum: unknown FERRUM_LOG item #{name.inspect} is ignored"
      []
    end

    # Parses `FERRUM_LOG_FORMAT`: `json`, `annotated` or `default`, which is
    # also what an empty or unknown value means.
    #
    # @param [String, nil] value
    #
    # @return [Symbol]
    def self.parse_format(value)
      format = value.to_s.strip
      return :default if format.empty?
      return format.to_sym if FORMATS.key?(format.to_sym)

      warn "Ferrum: unknown FERRUM_LOG_FORMAT #{format.inspect}, using default"
      :default
    end

    # Parses `FERRUM_LOG_COLOR`, anything but `always` or `never` means `:auto`.
    #
    # @param [String, nil] value
    #
    # @return [Symbol]
    def self.parse_color(value)
      %w[always never].include?(value.to_s.strip) ? value.strip.to_sym : :auto
    end

    # Encodes a CDP message, or a part of it, as JSON with string values longer
    # than {VALUE_LENGTH} shortened, e.g. Base64 screenshots.
    # `FERRUM_LOG_VALUE_LENGTH=0` keeps them whole. Messages nest as deep as
    # Chrome sends them, e.g. a DOM tree, so there's no nesting limit.
    #
    # @param [Object] value
    #
    # @return [String]
    def self.dump(value)
      JSON.generate(truncate(value), max_nesting: false)
    end

    # Shortens string values longer than {VALUE_LENGTH} anywhere in a CDP
    # message.
    #
    # @param [Object] value
    #
    # @return [Object]
    def self.truncate(value)
      case value
      when Hash then value.transform_values { |item| truncate(item) }
      when Array then value.map { |item| truncate(item) }
      when String
        return value if VALUE_LENGTH.zero? || value.size <= VALUE_LENGTH

        "#{value[0, VALUE_LENGTH]}... (#{value.size - VALUE_LENGTH} more characters)"
      else value
      end
    end

    def initialize(logger, channels: CHANNELS, only: [], skip: [], format: :default, color: :auto)
      @logger = logger
      @channels = channels
      @only = only
      @skip = skip
      @color = case color
               when :always then true
               when :never then false
               else logger.respond_to?(:tty?) && logger.tty? && ENV.fetch("NO_COLOR", "").empty?
               end
      @formatter = FORMATS.fetch(format).new(color: @color)
      @commands = Concurrent::Map.new if format == :annotated || only.any? || skip.any?
      @mutex = Mutex.new
    end

    # Whether the channel is written to the logger.
    #
    # @param [Symbol] channel
    #
    # @return [Boolean]
    def enabled?(channel)
      channels.include?(channel)
    end

    # Writes a CDP message sent to the browser.
    #
    # @param [Hash{Symbol => Object}] message
    #
    # @param [Object] connection
    #   What the message was sent over, command ids are unique per connection.
    #
    # @return [void]
    def sent(message, connection = nil)
      return unless enabled?(:protocol)

      @commands&.[]=([connection, message[:id]], [message[:method], Utils::ElapsedTime.monotonic_time])
      return unless show?(message[:method])

      write(:protocol) { @formatter.sent(message, Utils::ElapsedTime.elapsed_time) }
    end

    # Writes a CDP message received from the browser.
    #
    # @param [Hash{String => Object}, nil] message
    #   The parsed message, `nil` when it couldn't be parsed.
    #
    # @param [String] raw
    #   The message as received.
    #
    # @param [Object] connection
    #   What the message was received over.
    #
    # @return [void]
    def received(message, raw, connection = nil)
      return unless enabled?(:protocol)

      command = answered_command(message, connection)
      return unless show?(message&.fetch("method", nil) || command&.first)

      write(:protocol) { @formatter.received(message, raw, Utils::ElapsedTime.elapsed_time, command) }
    end

    # Writes a line of the browser process output.
    #
    # @param [String] line
    #
    # @return [void]
    def browser(line)
      write(:browser) { line }
    end

    private

    def answered_command(message, connection)
      return unless @commands && message&.key?("id")

      method, sent_at = @commands.delete([connection, message["id"]])
      [method, Utils::ElapsedTime.monotonic_time - sent_at] if method
    end

    def show?(method)
      return true unless method

      (only.empty? || matches?(only, method)) && !matches?(skip, method)
    end

    def matches?(patterns, method)
      patterns.any? { |pattern| File.fnmatch?(pattern, method) }
    end

    def write(channel, &block)
      return unless enabled?(channel)

      if logger.respond_to?(:debug)
        logger.debug("ferrum:#{channel}", &block)
      else
        line = block.call
        @mutex.synchronize { logger.puts(line) }
      end
    rescue StandardError => e
      warn "Ferrum: couldn't write to the logger, #{e.class}: #{e.message}" unless @write_failed
      @write_failed = true
    end
  end
end
