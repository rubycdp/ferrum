# frozen_string_literal: true

module Ferrum
  class Target
    NEW_WINDOW_WAIT = ENV.fetch("FERRUM_NEW_WINDOW_WAIT", 0.3).to_f

    # You can create page yourself and assign it to target, used in cuprite
    # where we enhance page class and build page ourselves.
    attr_writer :page

    def initialize(client, params = nil)
      @page = nil
      @client = client
      @params = params
    end

    def update(params)
      @params = params
    end

    def attached?
      !!@page
    end

    def page
      @page ||= build_page
    end

    def build_page(**options)
      maybe_sleep_if_new_window
      Page.new(@client, context_id: context_id, target_id: id, **options)
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

    def maybe_sleep_if_new_window
      # Dirty hack because new window doesn't have events at all
      sleep(NEW_WINDOW_WAIT) if window?
    end
  end
end
