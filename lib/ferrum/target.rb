# frozen_string_literal: true

module Ferrum
  class Target
    NEW_WINDOW_WAIT = ENV.fetch("FERRUM_NEW_WINDOW_WAIT", 0.3).to_f

    def initialize(browser, params = nil)
      @browser = browser
      @params = params
    end

    def update(params)
      @params = params
    end

    def page
      @page ||= begin
        # Dirty hack because new window doesn't have events at all
        sleep(NEW_WINDOW_WAIT) if window?
        Page.new(id, @browser)
      end
    end

    def id
      @params["targetId"]
    end

    def type
      @params["type"]
    end

    def title
      @params["title"]
    end

    def url
      @params["url"]
    end

    def opener_id
      @params["openerId"]
    end

    def context_id
      @params["browserContextId"]
    end

    def window?
      !!opener_id
    end
  end
end
