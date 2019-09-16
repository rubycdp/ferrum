# frozen_string_literal: true

require "ferrum/network/error"
require "ferrum/network/request"
require "ferrum/network/response"

module Ferrum
  class Network
    class Exchange
      attr_reader :request, :response, :error

      def initialize(params)
        @response = @error = nil
        build_request(params)
      end

      def build_request(params)
        @request = Network::Request.new(params)
      end

      def build_response(params)
        @response = Network::Response.new(params)
      end

      def build_error(params)
        @error = Network::Error.new(params)
      end

      def navigation_request?(frame_id)
        request.type?(:document) &&
          request.frame_id == frame_id
      end

      def blocked?
        response.nil?
      end

      def to_a
        [request, response, error]
      end
    end
  end
end
