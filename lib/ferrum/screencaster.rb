# frozen_string_literal: true

module Ferrum
  class Screencaster
    def initialize(page)
      @page = page
    end

    def add_frame(params)
      warn "frame"
      @page.command("Page.screencastFrameAck", sessionId: params["sessionId"])

      ts = (Time.now.to_f * 1000).to_i
      File.binwrite("img_#{ts}.jpeg", Base64.decode64(params["data"]))
    end

    def start_screencast
      @page.command("Page.startScreencast", format: "jpeg")
    end

    def stop_screencast
      warn "stopped"
      @page.command("Page.stopScreencast")
    end
  end
end
