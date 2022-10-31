# frozen_string_literal: true

require "ferrum/cookies/cookie"

module Ferrum
  class Cookies
    def initialize(page)
      @page = page
    end

    #
    # Returns cookies hash.
    #
    # @return [Hash{String => Cookie}]
    #
    # @example
    #   browser.cookies.all # => {
    #   #  "NID" => #<Ferrum::Cookies::Cookie:0x0000558624b37a40 @attributes={
    #   #     "name"=>"NID", "value"=>"...", "domain"=>".google.com", "path"=>"/",
    #   #     "expires"=>1583211046.575681, "size"=>178, "httpOnly"=>true, "secure"=>false, "session"=>false
    #   #  }>
    #   # }
    #
    def all
      cookies = @page.command("Network.getAllCookies")["cookies"]
      cookies.to_h { |c| [c["name"], Cookie.new(c)] }
    end

    #
    # Returns cookie.
    #
    # @param [String] name
    #   The cookie name to fetch.
    #
    # @return [Cookie, nil]
    #   The cookie with the matching name.
    #
    # @example
    #   browser.cookies["NID"] # =>
    #   # <Ferrum::Cookies::Cookie:0x0000558624b67a88 @attributes={
    #   #  "name"=>"NID", "value"=>"...", "domain"=>".google.com",
    #   #  "path"=>"/", "expires"=>1583211046.575681, "size"=>178,
    #   #  "httpOnly"=>true, "secure"=>false, "session"=>false
    #   # }>
    #
    def [](name)
      all[name]
    end

    #
    # Sets a cookie.
    #
    # @param [Hash{Symbol => Object}, Cookie] options
    #
    # @option options [String] :name
    #
    # @option options [String] :value
    #
    # @option options [String] :domain
    #
    # @option options [String] :path
    #
    # @option options [Integer] :expires
    #
    # @option options [Integer] :size
    #
    # @option options [Boolean] :httponly
    #
    # @option options [Boolean] :secure
    #
    # @option options [String] :samesite
    #
    #
    # @example
    #   browser.cookies.set(name: "stealth", value: "omg", domain: "google.com") # => true
    #
    # @example
    #   nid_cookie = browser.cookies["NID"] # => <Ferrum::Cookies::Cookie:0x0000558624b67a88>
    #   browser.cookies.set(nid_cookie) # => true
    #
    def set(options)
      cookie = (
        options.is_a?(Cookie) ? options.attributes : options
      ).dup.transform_keys(&:to_sym)

      cookie[:domain] ||= default_domain

      cookie[:httpOnly] = cookie.delete(:httponly) if cookie.key?(:httponly)
      cookie[:sameSite] = cookie.delete(:samesite) if cookie.key?(:samesite)

      expires = cookie.delete(:expires).to_i
      cookie[:expires] = expires if expires.positive?

      @page.command("Network.setCookie", **cookie)["success"]
    end

    #
    # Removes given cookie.
    #
    # @param [String] name
    #
    # @param [Hash{Symbol => Object}] options
    #   Additional keyword arguments.
    #
    # @option options [String] :domain
    #
    # @option options [String] :url
    #
    # @example
    #   browser.cookies.remove(name: "stealth", domain: "google.com") # => true
    #
    def remove(name:, **options)
      raise "Specify :domain or :url option" if !options[:domain] && !options[:url] && !default_domain

      options = options.merge(name: name)
      options[:domain] ||= default_domain

      @page.command("Network.deleteCookies", **options)

      true
    end

    #
    # Removes all cookies for current page.
    #
    # @return [true]
    #
    # @example
    #   browser.cookies.clear # => true
    #
    def clear
      @page.command("Network.clearBrowserCookies")
      true
    end

    private

    def default_domain
      URI.parse(@page.browser.base_url).host if @page.browser.base_url
    end
  end
end
