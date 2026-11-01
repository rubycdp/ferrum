# frozen_string_literal: true

module Ferrum
  class Page
    #
    # The cookies one page sees: the ones sent to its URL and the URLs of its
    # frames, via the CDP `Network` domain. The page shares them with every
    # other page in its {Context}, `context.cookies` has all of them whatever
    # their domain.
    #
    class Cookies
      include Ferrum::Cookies::Collection

      def initialize(page)
        @page = page
      end

      #
      # Enumerates over the page's cookies.
      #
      # @param [Array<String>, nil] urls
      #   The URLs to get the cookies for instead of the page's and its frames'.
      #
      # @yield [cookie]
      #   The given block will be passed each cookie.
      #
      # @yieldparam [Ferrum::Cookies::Cookie] cookie
      #
      # @return [Enumerator]
      #   If no block is given, an Enumerator object will be returned.
      #
      # @example
      #   page.cookies.each { |cookie| puts cookie.name }
      #   page.cookies.each(urls: ["https://accounts.google.com"]).map(&:name) # => ["SID"]
      #
      def each(urls: nil)
        return enum_for(__method__, urls: urls) unless block_given?

        params = { urls: urls } if urls
        cookies = @page.command("Network.getCookies", **Hash(params))["cookies"]

        cookies.each do |c|
          yield Ferrum::Cookies::Cookie.new(c)
        end
      end

      #
      # Sets a cookie, see {Ferrum::Cookies#set} for the options. Without
      # `:domain` or `:url` it's set for the page's host, or the `:base_url`
      # host before the page has loaded anything.
      #
      # @param [Hash{Symbol => Object}, Ferrum::Cookies::Cookie] options
      #
      # @return [Boolean]
      #
      # @example
      #   page.cookies.set(name: "stealth", value: "omg") # => true
      #
      def set(options)
        cookie = cookie_params(options)
        cookie[:domain] ||= default_domain unless cookie[:url]

        @page.command("Network.setCookie", **cookie)["success"]
      end

      #
      # Removes the cookies with the given name, on the page's host unless
      # `:domain` or `:url` is given.
      #
      # @param [String] name
      #
      # @param [Hash{Symbol => Object}] options
      #
      # @option options [String] :domain
      #   The exact domain of the cookie.
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
      #   page.cookies.remove(name: "stealth") # => true
      #
      def remove(name:, **options)
        raise "Specify :domain or :url option" if !options[:domain] && !options[:url] && !default_domain

        options = options.merge(name: name)
        options[:domain] ||= default_domain unless options[:url]

        @page.command("Network.deleteCookies", **options)

        true
      end

      #
      # Removes the page's cookies, the ones {#each} yields. Cookies on other
      # domains stay, `context.cookies.clear` removes them too.
      #
      # @return [true]
      #
      # @example
      #   page.cookies.clear # => true
      #
      def clear
        each do |cookie|
          @page.command("Network.deleteCookies", name: cookie.name, domain: cookie.domain, path: cookie.path)
        end

        true
      end

      private

      def default_domain
        uri = URI.parse(@page.url.to_s)
        %w[http https].include?(uri.scheme) ? uri.host : base_domain(@page.base_url)
      end
    end
  end
end
