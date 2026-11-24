# frozen_string_literal: true

module Ferrum
  #
  # Manages the extra HTTP headers a page sends with its requests, via the
  # CDP `Network.setExtraHTTPHeaders` command. A `User-Agent` or
  # `Accept-Language` header is only sent with requests, use
  # {Network#emulate} to change what `navigator` reports too.
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
    # @return [nil]
    #
    # @raise [TimeoutError]
    #
    def set(headers)
      @headers = {}
      add(headers)
    end

    #
    # Clear all headers.
    #
    # @return [nil]
    #
    # @raise [TimeoutError]
    #
    def clear
      @headers = {}
      @page.command("Network.setExtraHTTPHeaders", headers: @headers)
      nil
    end

    #
    # Adds given headers to already set ones.
    #
    # @param [Hash{String => String}] headers
    #   key-value pairs for example `"Referer" => "http://example.com"`.
    #
    # @return [nil]
    #
    # @raise [TimeoutError]
    #
    def add(headers)
      @headers.merge!(headers)
      @page.command("Network.setExtraHTTPHeaders", headers: @headers)
      nil
    end
  end
end
