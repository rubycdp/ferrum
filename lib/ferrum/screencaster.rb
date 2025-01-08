# frozen_string_literal: true
require 'fileutils'

# Combine the resulting frames together into a video with:
# ffmpeg -y -framerate 30 -i 'frame-%d.jpeg' -c:v libx264 -r 30 -pix_fmt yuv420p output.mp4
#
module Ferrum
  class Screencaster
    def initialize(page)
      @page = page
      @frame_number = 0
      @threads = []
      @save_path
    end

    def add_frame(params)
      @page.command("Page.screencastFrameAck", sessionId: params["sessionId"])

      t = Thread.new { File.binwrite("#{@save_path}/frame-#{@frame_number}.jpeg", Base64.decode64(params["data"])) }
      @frame_number += 1
      @threads << t
      true
    end


		# save_path: Directory where individual frames from the screencast will be saved
    def start_screencast(save_path)
      @save_path = save_path
      raise "Save path for screen recording does not exist" unless Dir.exist?(@save_path)
      @page.command("Page.startScreencast", format: "jpeg")
    end

    def stop_screencast
      @threads.each(&:join)
      @page.command("Page.stopScreencast")
    end
  end
end
