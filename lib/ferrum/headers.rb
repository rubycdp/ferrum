# frozen_string_literal: true

module Ferrum
  #
  # Manages the extra HTTP headers a page sends with its requests, via the
  # CDP `Network.setExtraHTTPHeaders` command. Setting a `User-Agent` or
  # `Accept-Language` header also updates the corresponding navigator
  # override so JavaScript sees consistent values, see {Network#emulate}.
  #
  class Headers
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
      clear
      add(headers)
    end

    #
    # Clear all headers.
    #
    # @return [true]
    #
    def clear
      @headers = {}
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
      @page.network.emulate(user_agent: @headers["User-Agent"], accept_language: @headers["Accept-Language"])
      @page.command("Network.setExtraHTTPHeaders", headers: @headers)
      true
    end
  end
end
