# frozen_string_literal: true

module Ferrum
  #
  # Manages the extra HTTP headers a page sends with its requests, via the
  # CDP `Network.setExtraHTTPHeaders` command. Setting a `User-Agent` or
  # `Accept-Language` header also updates the corresponding navigator
  # override so JavaScript sees consistent values, see {Network#emulate}.
  # Headers that don't contain one of them leave the override alone.
  #
  class Headers
    OVERRIDES = { user_agent: "User-Agent", accept_language: "Accept-Language" }.freeze

    def initialize(page)
      @page = page
      @headers = {}
    end

    #
    # Get all headers.
    #
    # @return [Hash{String => String}]
    #
    def get
      @headers
    end

    #
    # Set given headers. Eventually clear all headers and set given ones.
    #
    # @param [Hash{String => String}] headers
    #   key-value pairs for example `"User-Agent" => "Browser"`.
    #
    # @return [true]
    #
    def set(headers)
      reset_overrides(keep: headers)
      @headers = {}
      add(headers)
    end

    #
    # Clear all headers, and the user agent and language they set.
    #
    # @return [true]
    #
    def clear
      reset_overrides
      @headers = {}
      @page.command("Network.setExtraHTTPHeaders", headers: @headers)
      true
    end

    #
    # Adds given headers to already set ones.
    #
    # @param [Hash{String => String}] headers
    #   key-value pairs for example `"Referer" => "http://example.com"`.
    #
    # @param [Boolean] permanent
    #
    # @return [true]
    #
    def add(headers, permanent: true)
      if headers["Referer"]
        @page.referrer = headers["Referer"]
        headers.delete("Referer") unless permanent
      end

      @headers.merge!(headers)
      overrides = OVERRIDES.select { |_, name| headers.key?(name) }.transform_values { |name| headers[name] }
      @page.network.emulate(**overrides) unless overrides.empty?
      @page.command("Network.setExtraHTTPHeaders", headers: @headers)
      true
    end

    private

    def reset_overrides(keep: {})
      dropped = OVERRIDES.select { |_, name| @headers.key?(name) && !keep.key?(name) }
      @page.network.emulate(**dropped.transform_values { nil }) unless dropped.empty?
    end
  end
end
