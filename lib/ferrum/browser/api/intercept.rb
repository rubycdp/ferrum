# frozen_string_literal: true

module Ferrum
  class Browser
    module API
      module Intercept
        def url_whitelist=(wildcards)
          @url_whitelist = prepare_wildcards(wildcards)
          page.intercept_request("*") if @client && !@url_whitelist.empty?
        end

        def url_blacklist=(wildcards)
          @url_blacklist = prepare_wildcards(wildcards)
          page.intercept_request("*") if @client && !@url_blacklist.empty?
        end

        private

        def prepare_wildcards(wc)
          Array(wc).map do |wildcard|
            if wildcard.is_a?(Regexp)
              wildcard
            else
              wildcard = wildcard.gsub("*", ".*")
              Regexp.new(wildcard, Regexp::IGNORECASE)
            end
          end
        end
      end
    end
  end
end
