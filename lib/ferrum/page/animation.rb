# frozen_string_literal: true

module Ferrum
  class Page
    module Animation
      def playback_rate
        command("Animation.getPlaybackRate")["playbackRate"]
      end

      def playback_rate=(value)
        command("Animation.setPlaybackRate", playbackRate: value)
      end
    end
  end
end
