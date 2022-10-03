# frozen_string_literal: true

module Ferrum
  class Cookies
    #
    # Represents a [cookie value](https://chromedevtools.github.io/devtools-protocol/1-3/Network/#type-Cookie).
    #
    class Cookie
      # The parsed JSON attributes.
      #
      # @return [Hash{String => String}]
      attr_reader :attributes

      #
      # Initializes the cookie.
      #
      # @param [Hash{String => String}] attributes
      #   The parsed JSON attributes.
      #
      def initialize(attributes)
        @attributes = attributes
      end

      #
      # The cookie's name.
      #
      # @return [String]
      #
      def name
        @attributes["name"]
      end

      #
      # The cookie's value.
      #
      # @return [String]
      #
      def value
        @attributes["value"]
      end

      #
      # The cookie's domain.
      #
      # @return [String]
      #
      def domain
        @attributes["domain"]
      end

      #
      # The cookie's path.
      #
      # @return [String]
      #
      def path
        @attributes["path"]
      end

      #
      # The `sameSite` configuration.
      #
      # @return ["Strict", "Lax", "None", nil]
      #
      def samesite
        @attributes["sameSite"]
      end

      #
      # The cookie's size.
      #
      # @return [Integer]
      #
      def size
        @attributes["size"]
      end

      #
      # Specifies whether the cookie is secure or not.
      #
      # @return [Boolean]
      #
      def secure?
        @attributes["secure"]
      end

      #
      # Specifies whether the cookie is HTTP-only or not.
      #
      # @return [Boolean]
      #
      def httponly?
        @attributes["httpOnly"]
      end

      #
      # Specifies whether the cookie is a session cookie or not.
      #
      # @return [Boolean]
      #
      def session?
        @attributes["session"]
      end

      #
      # Specifies when the cookie will expire.
      #
      # @return [Time, nil]
      #
      def expires
        Time.at(@attributes["expires"]) if @attributes["expires"].positive?
      end
    end

    def initialize(page)
      @page = page
    end

    #
    # Returns cookies hash.
    #
    # @return [Hash{String => Cookie}]
    #
    # @example
    #   browser.cookies.all # => {"NID"=>#<Ferrum::Cookies::Cookie:0x0000558624b37a40 @attributes={"name"=>"NID", "value"=>"...", "domain"=>".google.com", "path"=>"/", "expires"=>1583211046.575681, "size"=>178, "httpOnly"=>true, "secure"=>false, "session"=>false}>}
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
    #   browser.cookies["NID"] # => <Ferrum::Cookies::Cookie:0x0000558624b67a88 @attributes={"name"=>"NID", "value"=>"...", "domain"=>".google.com", "path"=>"/", "expires"=>1583211046.575681, "size"=>178, "httpOnly"=>true, "secure"=>false, "session"=>false}>
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
    # @option options [Integer] :expires
    #
    # @option options [String] :samesite
    #
    # @option options [Boolean] :httponly
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

    # Supports :url, :domain and :path options
    def remove(name:, **options)
      raise "Specify :domain or :url option" if !options[:domain] && !options[:url] && !default_domain

      options = options.merge(name: name)
      options[:domain] ||= default_domain

      @page.command("Network.deleteCookies", **options)

      true
    end

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
