# frozen_string_literal: true

module Ferrum
  #
  # Manages the extra HTTP headers a page sends with its requests, via the
  # CDP `Network.setExtraHTTPHeaders` command. Setting a `User-Agent` or
  # `Accept-Language` header also changes what `navigator` reports, which is
  # deprecated and will stop in Ferrum 0.22, use {Network#emulate} for that.
  # Headers that don't contain one of them leave the override alone.
  #
  class Headers
    OVERRIDES = { user_agent: "User-Agent", accept_language: "Accept-Language" }.freeze
    OVERRIDES_DEPRECATED = "User-Agent and Accept-Language set through headers will only be sent with requests in " \
                           "Ferrum 0.22 and no longer change what navigator reports. " \
                           "Use network.emulate(user_agent:, accept_language:) to override both."

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
    # @raise [TimeoutError]
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
    # @raise [TimeoutError]
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
    # @return [true]
    #
    # @raise [TimeoutError]
    #
    def add(headers)
      @headers.merge!(headers)
      overrides = OVERRIDES.select { |_, name| headers.key?(name) }.transform_values { |name| headers[name] }
      unless overrides.empty?
        Utils::Deprecate.warn(OVERRIDES_DEPRECATED, user_code: true)
        @page.network.emulate(**overrides)
      end
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
