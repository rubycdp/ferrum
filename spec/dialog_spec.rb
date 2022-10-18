# frozen_string_literal: true

describe Ferrum::Dialog do
  describe "#accept" do
    it "works with nested modals" do
      browser.go_to("/ferrum/with_js")
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
        window.open("/ferrum/with_js", "popup")
      JS

      popup, = browser.windows(:last)

      popup.on(:dialog) do |dialog, _index, _total|
        dialog.accept
      end
      popup.at_css("a#open-match").click
      expect(popup.at_xpath("//a[@id='open-match' and @confirmed='true']")).to be

      popup.close
    end
  end

  describe "#dismiss" do
    it "works with second window" do
      browser.go_to

      browser.execute <<-JS
        window.open("/ferrum/with_js", "popup")
      JS

      popup, = browser.windows(:last)

      popup.on(:dialog) do |dialog, _index, _total|
        dialog.dismiss
      end
      popup.at_css("a#open-match").click
      expect(popup.at_xpath("//a[@id='open-match' and @confirmed='true']")).not_to be

      popup.close
    end
  end

  describe "#match?" do
    it "matches on partial strings" do
      browser.go_to("/ferrum/with_js")
      browser.on(:dialog) do |dialog, _index, _total|
        if dialog.match?(Regexp.escape("[reg.exp] (chara©+er$)"))
          dialog.accept
        else
          dialog.dismiss
        end
      end

      browser.at_css("a#open-match").click

      expect(browser.at_xpath("//a[@id='open-match' and @confirmed='true']")).to be
    end

    it "matches on regular expressions" do
      browser.go_to("/ferrum/with_js")
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
