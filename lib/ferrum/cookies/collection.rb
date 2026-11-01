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
      # @deprecated Will be removed in Ferrum 0.22, it keeps one cookie per
      #   name. Use `to_a`, or `map(&:name)` for the names.
      #
      # Returns cookies hash.
      #
      # @param [Hash] options
      #   Passed to `each`.
      #
      # @return [Hash{String => Cookie}]
      #
      # @example
      #   page.cookies.all # => {
      #   #  "NID" => #<Ferrum::Cookies::Cookie:0x0000558624b37a40 @attributes={
      #   #     "name"=>"NID", "value"=>"...", "domain"=>".google.com", "path"=>"/",
      #   #     "expires"=>1583211046.575681, "size"=>178, "httpOnly"=>true, "secure"=>false, "session"=>false
      #   #  }>
      #   # }
      #
      def all(**options)
        Utils::Deprecate.warn(
          "cookies.all will be removed in Ferrum 0.22, it keeps one cookie per name. " \
          "Use cookies.to_a, or cookies.map(&:name) for the names.",
          user_code: true
        )
        each(**options).to_h do |cookie|
          [cookie.name, cookie]
        end
      end

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
        cookie = (options.is_a?(Cookie) ? options.attributes : options).dup.transform_keys(&:to_sym)

        cookie[:httpOnly] = cookie.delete(:httponly) if cookie.key?(:httponly)
        cookie[:sameSite] = cookie.delete(:samesite) if cookie.key?(:samesite)

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
