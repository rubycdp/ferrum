# frozen_string_literal: true

require "spec_helper"

module Ferrum
  describe Browser do
    context "dialog support" do
      it "matches on partial strings" do
        browser.goto("/ferrum/with_js")
        browser.on(:dialog) do |dialog|
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
        browser.goto("/ferrum/with_js")
        browser.on(:dialog) do |dialog|
          if dialog.match?(/^.t.ext.*\[\w{3}\.\w{3}\]/i)
            dialog.accept
          else
            dialog.dismiss
          end
        end

        browser.at_css("a#open-match").click

        expect(browser.at_xpath("//a[@id='open-match' and @confirmed='true']")).to be
      end

      it "works with nested modals" do
        browser.goto("/ferrum/with_js")
        browser.on(:dialog) do |dialog|
          if dialog.match?("Are you sure?")
            dialog.accept
          elsif dialog.match?("Are you really sure?")
            dialog.dismiss
          else
            dialog.dismiss
          end
        end

        browser.at_css("a#open-twice").click

        expect(browser.at_xpath("//a[@id='open-twice' and @confirmed='false']")).to be
      end

      it "works with second window", skip: true do
        browser.goto

        popup = browser.window_opened_by do
          browser.execute <<-JS
            window.open("/ferrum/with_js", "popup")
          JS
        end

        browser.within_window(popup) do
          browser.on(:dialog) { |d| d.accept }
          browser.at_css("a#open-match").click
          expect(browser.at_xpath("//a[@id='open-match' and @confirmed='true']")).to be
        end

        popup.close
      end
    end
  end
end
