# frozen_string_literal: true

module Ferrum
  class Dialog
    attr_reader :message, :default_prompt

    def initialize(page, params)
      @page = page
      @message = params["message"]
      @default_prompt = params["defaultPrompt"]
    end

    def accept(prompt_text = nil)
      options = { accept: true }
      response = prompt_text || default_prompt
      options.merge!(promptText: response) if response
      @page.command("Page.handleJavaScriptDialog", **options)
    end

    def dismiss
      @page.command("Page.handleJavaScriptDialog", accept: false)
    end

    def match?(regexp)
      !!message.match(regexp)
    end
  end
end
