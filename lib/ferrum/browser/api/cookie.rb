# frozen_string_literal: true

module Ferrum
  class Browser
    module API
      module Cookie
        def cookies
          cookies = page.command("Network.getAllCookies")["cookies"]
          cookies.map { |c| [c["name"], ::Ferrum::Cookie.new(c)] }.to_h
        end

        def set_cookie(name: nil, value: nil, **options)
          cookie = options.dup
          cookie[:name]   ||= name
          cookie[:value]  ||= value
          cookie[:domain] ||= default_domain

          expires = cookie.delete(:expires).to_i
          cookie[:expires] = expires if expires > 0

          page.command("Network.setCookie", **cookie)
        end

        # Supports :url, :domain and :path options
        def remove_cookie(name:, **options)
          raise "Specify :domain or :url option" if !options[:domain] && !options[:url] && !default_domain

          options = options.merge(name: name)
          options[:domain] ||= default_domain

          page.command("Network.deleteCookies", **options)
        end

        def clear_cookies
          page.command("Network.clearBrowserCookies")
        end

        private

        def default_domain
          URI.parse(base_url).host if base_url
        end
      end
    end
  end
end
