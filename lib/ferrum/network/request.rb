# frozen_string_literal: true

require "time"

module Ferrum::Network
  class Request
    attr_accessor :response, :error

    def initialize(data)
      @data = data
    end

    def id
      @data["id"]
    end

    def url
      @data["url"]
    end

    def method
      @data["method"]
    end

    def headers
      @data["headers"]
    end

    def time
      @time ||= Time.strptime(@data["time"].to_s, "%s")
    end
  end
end
