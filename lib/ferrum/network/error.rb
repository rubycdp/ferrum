# frozen_string_literal: true

module Ferrum
  class Network
    #
    # Represents a network-level loading error reported for a request,
    # e.g. via `Network.loadingFailed`. Distinct from the Ruby exceptions
    # defined in `ferrum/errors.rb`.
    #
    class Error
      # @note The writer is a private API, Ferrum sets it.
      attr_reader :id, :url, :type, :error_text, :description

      # @api private
      attr_writer :canceled, :id, :url, :type, :error_text, :monotonic_time, :description, :time

      # Whether the request was canceled.
      #
      # @return [Boolean]
      def canceled?
        @canceled
      end

      # When the request failed.
      #
      # @return [Time, nil]
      #
      # @note The writer is a private API, Ferrum sets it.
      attr_reader :time

      # Sets the error's timestamp, deriving {#time} from it.
      #
      # @param [Float] value
      #   Timestamp in milliseconds since epoch, as reported by
      #   `Log.entryAdded`.
      #
      # @return [Float]
      #
      # @api private
      def timestamp=(value)
        @timestamp = value
        @time = Time.at(value / 1000.0)
      end
    end
  end
end
