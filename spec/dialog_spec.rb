# frozen_string_literal: true

describe Ferrum::Dialog do
  def open_prompt(&block)
    browser.on(:dialog) { |dialog, _index, _total| block.call(dialog) }
    browser.go_to
    browser.execute(%(setTimeout(() => window.result = prompt("Your name?", "Bob"))))
  end

  describe "#message" do
    it "returns the text of the dialog" do
      messages = Concurrent::Array.new
      open_prompt do |dialog|
        messages << dialog.message
        dialog.dismiss
      end

      wait_for { messages }.to eq(["Your name?"])
    end
  end

  describe "#default_prompt" do
    it "returns the default text of a prompt" do
      defaults = Concurrent::Array.new
      open_prompt do |dialog|
        defaults << dialog.default_prompt
        dialog.dismiss
      end

      wait_for { defaults }.to eq(["Bob"])
    end
  end

  describe "#accept" do
    it "works with nested modals" do
      browser.go_to("/with_js")
      browser.on(:dialog) do |dialog, _index, _total|
        if dialog.match?("Are you sure?")
          dialog.accept
        else
          dialog.dismiss
        end
      end

      browser.at_css("a#open-twice").click

      expect(browser.at_xpath("//a[@id='open-twice' and @confirmed='false']")).to be
    end

    it "works with second window" do
      browser.go_to

      browser.execute <<-JS
        window.open("/with_js", "popup")
      JS

      popup, = browser.windows(:last)

      popup.on(:dialog) do |dialog, _index, _total|
        dialog.accept
      end
      popup.at_css("a#open-match").click
      expect(popup.at_xpath("//a[@id='open-match' and @confirmed='true']")).to be

      popup.close
    end

    it "fills a prompt with the given text" do
      open_prompt { |dialog| dialog.accept("Alice") }

      wait_for { browser.evaluate("window.result") }.to eq("Alice")
    end

    it "fills a prompt with its default text when no text is given" do
      open_prompt(&:accept)

      wait_for { browser.evaluate("window.result") }.to eq("Bob")
    end
  end

  describe "#dismiss" do
    it "works with second window" do
      browser.go_to

      browser.execute <<-JS
        window.open("/with_js", "popup")
      JS

      popup, = browser.windows(:last)

      popup.on(:dialog) do |dialog, _index, _total|
        dialog.dismiss
      end
      popup.at_css("a#open-match").click
      expect(popup.at_xpath("//a[@id='open-match' and @confirmed='true']")).not_to be

      popup.close
    end

    it "cancels a prompt" do
      open_prompt(&:dismiss)

      wait_for { browser.evaluate("'result' in window") }.to be(true)
      expect(browser.evaluate("window.result")).to be_nil
    end
  end

  describe "#match?" do
    it "matches on partial strings" do
      browser.go_to("/with_js")
      browser.on(:dialog) do |dialog, _index, _total|
        if dialog.match?("[reg.exp] (chara©+er$)")
          dialog.accept
        else
          dialog.dismiss
        end
      end

      browser.at_css("a#open-match").click

      expect(browser.at_xpath("//a[@id='open-match' and @confirmed='true']")).to be
    end

    it "treats string patterns literally instead of as regexps" do
      browser.go_to("/with_js")
      browser.on(:dialog) do |dialog, _index, _total|
        if dialog.match?("[reg.exp?]")
          dialog.accept
        else
          dialog.dismiss
        end
      end

      browser.at_css("a#open-match").click

      expect(browser.at_xpath("//a[@id='open-match' and @confirmed='true']")).not_to be
    end

    it "matches on regular expressions" do
      browser.go_to("/with_js")
      browser.on(:dialog) do |dialog, _index, _total|
        if dialog.match?(/^.t.ext.*\[\w{3}\.\w{3}\]/i)
          dialog.accept
        else
          dialog.dismiss
        end
      end

      browser.at_css("a#open-match").click

      expect(browser.at_xpath("//a[@id='open-match' and @confirmed='true']")).to be
    end
  end
end
