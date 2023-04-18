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
        warn 'frame'
        @page.command("Page.screencastFrameAck", sessionId: params["sessionId"])
        img = params["data"]
        img_decoded = Base64.decode64(img)
        @stdin.write(img_decoded)

      end

      def start_screencast #(options)
        cmd = "ffmpeg -y -f image2pipe -i - -c:v libx264 -preset slow -crf 22 -r 1 -an -f mp4 -movflags +faststart output_video2.mp4"
        @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(cmd)
        @page.command("Page.startScreencast", format: "jpeg") #, **options)
      end

      def stop_screencast
        warn 'stopped'
        @page.command("Page.stopScreencast")
        @stdin.close
        @stdout.close
        @stderr.close
        @wait_thr.join
      end
  end
end
