# frozen_string_literal: true

require "yaml"
require "ferrum/cookies/cookie"
require "ferrum/cookies/collection"

module Ferrum
  #
  # Manages the cookies of a browser {Context}, which every page in it shares,
  # via the CDP `Storage` domain. Enumerable over all of them whatever their
  # domain, and provides methods to read, set, remove and clear them, as well
  # as persist them to/from a YAML file. {Page::Cookies} narrows them down to
  # what one page sees.
  #
  class Cookies
    include Collection

    def initialize(client, context_id)
      @client = client
      @context_id = context_id
    end

    #
    # Enumerates over all cookies in the context.
    #
    # @yield [cookie]
    #   The given block will be passed each cookie.
    #
    # @yieldparam [Cookie] cookie
    #   A cookie in the context.
    #
    # @return [Enumerator]
    #   If no block is given, an Enumerator object will be returned.
    #
    def each
      return enum_for(__method__) unless block_given?

      cookies = @client.command("Storage.getCookies", browserContextId: @context_id)["cookies"]

      cookies.each do |c|
        yield Cookie.new(c)
      end
    end

    #
    # Sets a cookie.
    #
    # @param [Hash{Symbol => Object}, Cookie] options
    #
    # @option options [String] :name
    #   The cookie param name.
    #
    # @option options [String] :value
    #   The cookie param value.
    #
    # @option options [String] :domain
    #   The domain the cookie belongs to, the `:base_url` host by default.
    #
    # @option options [String] :url
    #   The URL to derive the domain and path from instead.
    #
    # @option options [String] :path
    #   The path that the cookie is bound to.
    #
    # @option options [Integer] :expires
    #   When the cookie will expire.
    #
    # @option options [Boolean] :httponly
    #   Specifies whether the cookie `HttpOnly`.
    #
    # @option options [Boolean] :secure
    #   Specifies whether the cookie is marked as `Secure`.
    #
    # @option options [String] :samesite
    #   Specifies whether the cookie is `SameSite`.
    #
    # @return [true]
    #
    # @raise [BrowserError] if neither `:domain`, `:url` nor `:base_url` is set.
    #
    # @example
    #   browser.cookies.set(name: "stealth", value: "omg", domain: "google.com") # => true
    #
    # @example
    #   nid_cookie = browser.cookies["NID"] # => <Ferrum::Cookies::Cookie:0x0000558624b67a88>
    #   browser.cookies.set(nid_cookie) # => true
    #
    def set(options)
      cookie = cookie_params(options)
      cookie[:domain] ||= default_domain unless cookie[:url]

      write(cookie)
      true
    end

    #
    # Removes the cookies with the given name, on the given domain or the ones
    # sent to the given URL.
    #
    # @param [String] name
    #
    # @param [Hash{Symbol => Object}] options
    #   Additional keyword arguments.
    #
    # @option options [String] :domain
    #   The exact domain of the cookie, the `:base_url` host by default.
    #
    # @option options [String] :url
    #   The URL the cookie is sent to.
    #
    # @option options [String] :path
    #   The exact path of the cookie.
    #
    # @return [true]
    #
    # @example
    #   browser.cookies.remove(name: "stealth", domain: "google.com") # => true
    #
    def remove(name:, **options)
      domain = options[:domain] || (default_domain unless options[:url])
      raise "Specify :domain or :url option" if !domain && !options[:url]

      uri = URI.parse(options[:url]) if options[:url]
      cookies = select do |cookie|
        cookie.name == name &&
          (options[:path].nil? || cookie.path == options[:path]) &&
          (domain ? cookie.domain == domain : sent_to?(cookie, uri))
      end
      cookies.each { |cookie| write(cookie.attributes.merge("expires" => 1)) }

      true
    end

    #
    # Removes all cookies in the context.
    #
    # @return [true]
    #
    # @example
    #   browser.cookies.clear # => true
    #
    def clear
      @client.command("Storage.clearCookies", browserContextId: @context_id)
      true
    end

    #
    # Stores all cookies in the context in a file.
    #
    # @return [Integer]
    #
    # @example
    #   browser.cookies.store # => Integer
    #
    def store(path = "cookies.yml")
      File.write(path, map(&:to_h).to_yaml)
    end

    #
    # Loads all cookies from the file and sets them in the context.
    #
    # @return [true]
    #
    # @example
    #   browser.cookies.load # => true
    #
    def load(path = "cookies.yml")
      cookies = YAML.load_file(path)
      cookies.each { |c| set(c) }
      true
    end

    private

    def write(cookie)
      @client.command("Storage.setCookies", cookies: [cookie], browserContextId: @context_id)
    end

    def default_domain
      base_domain(@client.options.base_url)
    end

    def sent_to?(cookie, uri)
      domain = cookie.domain
      host_match = uri.host == domain.delete_prefix(".") || (domain.start_with?(".") && uri.host.end_with?(domain))
      path = uri.path.to_s.empty? ? "/" : uri.path
      host_match && path.start_with?(cookie.path.to_s)
    end
  end
end
