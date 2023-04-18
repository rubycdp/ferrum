# frozen_string_literal: true
require "ferrum/screencaster"


module Ferrum
  class Page
    module Screencast
      attr_reader :screencaster

      def start_screencast #(options)
        @screencaster.start_screencast
      end

      def stop_screencast
        @screencaster.stop_screencast
      end
    end
  end
end
