# frozen_string_literal: true

module Ferrum
  class Network
    #
    # Represents a network-level loading error reported for a request,
    # e.g. via `Network.loadingFailed`. Distinct from the Ruby exceptions
    # defined in `ferrum/errors.rb`.
    #
    class Error
      TIMESTAMP_DEPRECATED = "timestamp will be removed in Ferrum 0.22. Use time instead."
      MONOTONIC_TIME_DEPRECATED = "monotonic_time will be removed in Ferrum 0.22. Use time instead."

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

      # @deprecated Will be removed in Ferrum 0.22. Use {#time}.
      #
      # @return [Float, nil]
      def timestamp
        Utils::Deprecate.warn(TIMESTAMP_DEPRECATED, user_code: true)
        @timestamp
      end

      # @deprecated Will be removed in Ferrum 0.22. Use {#time}.
      #
      # @return [Float, nil]
      def monotonic_time
        Utils::Deprecate.warn(MONOTONIC_TIME_DEPRECATED, user_code: true)
        @monotonic_time
      end

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
