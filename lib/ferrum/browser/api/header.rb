# frozen_string_literal: true

module Ferrum
  class Browser
    module API
      module Header
        def headers=(headers)
          @headers = {}
          add_headers(headers)
        end

        def add_headers(headers, permanent: true)
          if headers["Referer"]
            page.referrer = headers["Referer"]
            headers.delete("Referer") unless permanent
          end

          @headers.merge!(headers)
          user_agent = @headers["User-Agent"]
          accept_language = @headers["Accept-Language"]

          set_overrides(user_agent: user_agent, accept_language: accept_language)
          page.command("Network.setExtraHTTPHeaders", headers: @headers)
        end

        def add_header(header, permanent: true)
          add_headers(header, permanent: permanent)
        end
      end
    end
  end
end
