# frozen_string_literal: true

module Ferrum
  class Cookies
    #
    # Reading cookies by name, shared by {Cookies} and {Page::Cookies}, both
    # of which define `each`.
    #
    module Collection
      include Enumerable

      #
      # Returns the first cookie with the given name, narrowed down by domain
      # and path when the name is used by more than one cookie.
      #
      # @param [String] name
      #   The cookie name to fetch.
      #
      # @param [String, nil] domain
      #   The exact domain of the cookie, e.g. `".example.com"` for one sent to
      #   every subdomain.
      #
      # @param [String, nil] path
      #   The exact path of the cookie.
      #
      # @return [Cookie, nil]
      #   The matching cookie.
      #
      # @example
      #   page.cookies["NID"] # =>
      #   # <Ferrum::Cookies::Cookie:0x0000558624b67a88 @attributes={
      #   #  "name"=>"NID", "value"=>"...", "domain"=>".google.com",
      #   #  "path"=>"/", "expires"=>1583211046.575681, "size"=>178,
      #   #  "httpOnly"=>true, "secure"=>false, "session"=>false
      #   # }>
      #
      # @example
      #   page.cookies["id", domain: "www.example.com", path: "/app"]
      #
      def [](name, domain: nil, path: nil)
        find do |cookie|
          cookie.name == name && (domain.nil? || cookie.domain == domain) && (path.nil? || cookie.path == path)
        end
      end

      private

      def cookie_params(options)
        cookie = (options.is_a?(Cookie) ? options.attributes : options).transform_keys(&:to_sym)
        cookie.transform_keys!(httponly: :httpOnly, http_only: :httpOnly, samesite: :sameSite, same_site: :sameSite)

        expires = cookie.delete(:expires).to_i
        cookie[:expires] = expires if expires.positive?

        cookie
      end

      def base_domain(base_url)
        URI.parse(base_url).host if base_url
      end
    end
  end
end
