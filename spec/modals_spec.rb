# frozen_string_literal: true

require "spec_helper"

module Ferrum
  describe Browser do
    context "modals support", skip: true do
      it "matches on partial strings" do
        browser.goto("/ferrum/with_js")
        expect do
          browser.accept_confirm "[reg.exp] (chara©+er$)" do
            browser.at_xpath("//a[text() = 'Open for match']").click
          end
        end.not_to raise_error
        expect(browser).to have_xpath("//a[@id='open-match' and @confirmed='true']")
      end

      it "matches on regular expressions" do
        browser.goto("/ferrum/with_js")
        expect do
          browser.accept_confirm(/^.t.ext.*\[\w{3}\.\w{3}\]/i) do
            browser.at_xpath("//a[text() = 'Open for match']").click
          end
        end.not_to raise_error
        expect(browser).to have_xpath("//a[@id='open-match' and @confirmed='true']")
      end

      it "works with nested modals" do
        browser.goto("/ferrum/with_js")
        expect do
          browser.dismiss_confirm "Are you really sure?" do
            browser.accept_confirm "Are you sure?" do
              browser.at_xpath("//a[text() = 'Open check twice']").click
            end
          end
        end.not_to raise_error
        expect(browser).to have_xpath("//a[@id='open-twice' and @confirmed='false']")
      end

      it "works with second window" do
        browser.goto

        popup = browser.window_opened_by do
          browser.execute <<-JS
            window.open("/ferrum/with_js", "popup")
          JS
        end

        browser.within_window(popup) do
          expect do
            browser.accept_confirm do
              browser.at_xpath("//a[text() = 'Open for match']").click
            end
            expect(browser).to have_xpath("//a[@id='open-match' and @confirmed='true']")
          end.not_to raise_error
        end
        popup.close
      end
    end
  end
end
