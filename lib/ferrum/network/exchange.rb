# frozen_string_literal: true

module Ferrum
  class Network
    class Exchange
      attr_reader :id
      attr_accessor :intercepted_request
      attr_accessor :request, :response, :error

      def initialize(page, id)
        @page, @id = page, id
        @intercepted_request = nil
        @request = @response = @error = nil
      end

      def navigation_request?(frame_id)
        request.type?(:document) &&
          request.frame_id == frame_id
      end

      def blank?
        !request
      end

      def blocked?
        intercepted_request && intercepted_request.status?(:aborted)
      end

      def finished?
        blocked? || response || error
      end

      def to_a
        [request, response, error]
      end

      def inspect
        "#<#{self.class} "\
        "@id=#{@id.inspect} "\
        "@intercepted_request=#{@intercepted_request.inspect} "\
        "@request=#{@request.inspect} "\
        "@response=#{@response.inspect} "\
        "@error=#{@error.inspect}>"
      end
    end
  end
end
