# frozen_string_literal: true

module Ferrum
  class Network
    class Error
      attr_writer :canceled
      attr_reader :time, :timestamp
      attr_accessor :id, :url, :type, :error_text, :monotonic_time, :description

      # Whether the request was canceled.
      #
      # @return [Boolean]
      def canceled?
        @canceled
      end

      # Sets the error's timestamp, deriving {#time} from it.
      #
      # @param [Float] value
      #   Timestamp in milliseconds since epoch, as reported by
      #   `Log.entryAdded`.
      #
      # @return [Float]
      def timestamp=(value)
        @timestamp = value
        @time = Time.strptime((value / 1000).to_s, "%s")
      end
    end
  end
end
