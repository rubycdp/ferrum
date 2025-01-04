# frozen_string_literal: true
require 'fileutils'

# Combine the resulting frames together into a video with:
# ffmpeg -y -framerate 30 -i 'frame-%d.jpeg' -c:v libx264 -r 30 -pix_fmt yuv420p try2.mp4
#
module Ferrum
  class Screencaster
    def initialize(page)
      @page = page
      @frame_number = 0
      @threads = []
      @base_dir = ""
    end

    def add_frame(params)
      warn "frame"

      @page.command("Page.screencastFrameAck", sessionId: params["sessionId"])

      t = Thread.new { File.binwrite("#{recordings_dir}/frame-#{@frame_number}.jpeg", Base64.decode64(params["data"])) }
      @frame_number += 1
      @threads << t
      true
    end

    def recordings_dir
      return @recordings_dir if defined? @recordings_dir

      timestamp = (Time.now.to_f * 1000).to_i
      @recordings_dir = FileUtils.mkdir_p("#{@base_dir}/screencast_recordings/#{timestamp}/").first
      @recordings_dir
    end

    def start_screencast(base_dir = "")
      @base_dir = base_dir
      @page.command("Page.startScreencast", format: "jpeg")
    end

    def stop_screencast
      warn "joining threads"
      @threads.each(&:join)
      warn "stopped"
      @page.command("Page.stopScreencast")
    end
  end
end
