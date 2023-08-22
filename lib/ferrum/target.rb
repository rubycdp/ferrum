# frozen_string_literal: true

module Ferrum
  class Target
    NEW_WINDOW_WAIT = ENV.fetch("FERRUM_NEW_WINDOW_WAIT", 0.3).to_f

    # You can create page yourself and assign it to target, used in cuprite
    # where we enhance page class and build page ourselves.
    attr_writer :page
    attr_reader :connection

    def initialize(browser, params = nil)
      @page = nil
      @browser = browser
      @params = params
    end

    def update(params)
      @params = params
    end

    def attached?
      !!@page
    end

    def page
      connection if page?
    end

    def network
      connection.network
    end

    def build(**options)
      connection(**options)
    end

    def build_page(**options)
      connection(**options)
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

    def page?
      @params["type"] == "page"
    end

    def worker?
      @params["type"] == "worker"
    end

    def maybe_sleep_if_new_window
      # Dirty hack because new window doesn't have events at all
      sleep(NEW_WINDOW_WAIT) if window?
    end

    def connection(**options)
      @connection ||= begin
        maybe_sleep_if_new_window if page?

        options.merge!(type: @params["type"])

        Page.new(id, @browser, **options)
      end
    end
  end
end
