# frozen_string_literal: true

module Ferrum::Network
  class Response
    attr_accessor :body_size

    def initialize(data)
      @data = data
    end

    def id
      @data["id"]
    end

    def url
      @data["url"]
    end

    def status
      @data["status"]
    end

    def status_text
      @data["statusText"]
    end

    def headers
      @data["headers"]
    end

    def headers_size
      @data["encodedDataLength"]
    end

    # FIXME: didn't check if we have it on redirect response
    def redirect_url
      @data["redirectURL"]
    end

    def content_type
      @content_type ||= @data.dig("headers", "contentType").sub(/;.*\z/, "")
    end
  end
end
