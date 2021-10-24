# frozen_string_literal: true

module Ferrum
  class Cookies
    class Cookie
      def initialize(attributes)
        @attributes = attributes
      end

      def name
        @attributes["name"]
      end

      def value
        @attributes["value"]
      end

      def domain
        @attributes["domain"]
      end

      def path
        @attributes["path"]
      end

      def samesite
        @attributes["sameSite"]
      end

      def size
        @attributes["size"]
      end

      def secure?
        @attributes["secure"]
      end

      def httponly?
        @attributes["httpOnly"]
      end

      def session?
        @attributes["session"]
      end

      def expires
        Time.at(@attributes["expires"]) if @attributes["expires"].positive?
      end
    end

    def initialize(page)
      @page = page
    end

    def all
      cookies = @page.command("Network.getAllCookies")["cookies"]
      cookies.map { |c| [c["name"], Cookie.new(c)] }.to_h
    end

    def [](name)
      all[name]
    end

    def set(name: nil, value: nil, **options)
      cookie = options.dup
      cookie[:name]   ||= name
      cookie[:value]  ||= value
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
