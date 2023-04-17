# frozen_string_literal: true

require 'open3'
require 'stringio'
#TODO these ^ need to be added to gemfile
require 'concurrent-ruby'

module Ferrum
  class Screencaster
 #   attr_reader :message, :default_prompt
      include Concurrent::Async

      def initialize(page)
        @page = page #might be wrong
        @stdin = StringIO.new
        @stdout = StringIO.new
        @stderr = StringIO.new
        @wait_thr = nil
      end

      def add_frame(params)
        @page.command("Page.screencastFrameAck")
        img = params["data"]
        img_decoded = Base64.decode64(img)
        @stdin.write(img_decoded)
      end

      def start_screencast #(options)
        cmd = "ffmpeg -y -f rawvideo -pix_fmt rgb24 -s 640x480 -r 30 -i - -vcodec mp4v -c:v libx264 -preset slow -crf 22 output_video.mp4"
        @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(cmd)
        @page.command("Page.startScreencast") #, **options)
      end

      def stop_screencast
        @page.command("Page.stopScreencast")
        @stdin.close
      end
  end
end
