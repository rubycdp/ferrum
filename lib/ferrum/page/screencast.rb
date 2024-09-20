# frozen_string_literal: true

module Ferrum
  class Page
    module Screencast

      # Starts yielding each frame to the given block.
      #
      # @param [Hash{Symbol => Object}] opts
      #
      # @option opts [:jpeg, :png] :format
      #   The format the image should be returned in.
      #
      # @option opts [Integer] :quality
      #   The image quality. **Note:** 0-100 works for jpeg only.
      #
      # @option opts [Integer] :max_width
      #   Maximum screenshot width.
      #
      # @option opts [Integer] :max_height
      #   Maximum screenshot height.
      #
      # @option opts [Integer] :every_nth_frame
      #   Send every n-th frame.
      #
      def start_screencast(**opts)

        options = opts.transform_keys { START_SCREENCAST_KEY_CONV.fetch(_1, _1) }
        response = command('Page.startScreencast', **options)

        if error_text = response["errorText"] # https://cs.chromium.org/chromium/src/net/base/net_error_list.h
          raise "Starting screencast failed (#{error_text})"
        end

        on('Page.screencastFrame') do |params|
          data, metadata, session_id = params.values_at('data', 'metadata', 'sessionId')

          command('Page.screencastFrameAck', sessionId: session_id)

          yield data, metadata, session_id
        end
      end

      # Stops sending each frame.
      def stop_screencast
        command('Page.stopScreencast')
      end

    private

      START_SCREENCAST_KEY_CONV = {
        max_width:       :maxWidth,
        max_height:      :maxHeight,
        every_nth_frame: :everyNthFrame,
      }.freeze
    end
  end
end
