# frozen_string_literal: true

require "spec_helper"

module Ferrum
  describe Browser do
    context "interception support" do
      it "blocks unwanted urls" do
        browser.intercept_request
        browser.on(:request_intercepted) do |request|
          request.match?(/unwanted/) ? request.abort : request.continue
        end

        browser.goto("/ferrum/url_blacklist")

        expect(browser.status).to eq(200)
        expect(browser.body).to include("We are loading some unwanted action here")

        frame = browser.at_xpath("//iframe[@name = 'framename']")
        browser.within_frame(frame) do
          expect(browser.body).not_to include("We shouldn't see this.")
        end
      end

      it "supports wildcards" do
        browser.intercept_request
        browser.on(:request_intercepted) do |request|
          request.match?(/.*wanted/) ? request.abort : request.continue
        end

        browser.goto("/ferrum/url_whitelist")

        expect(browser.status).to eq(200)
        expect(browser.body).to include("We are loading some wanted action here")

        frame = browser.at_xpath("//iframe[@name = 'framename']")
        browser.within_frame(frame) do
          expect(browser.body).not_to include("We should see this.")
        end

        frame = browser.at_xpath("//iframe[@name = 'unwantedframe']")
        browser.within_frame(frame) do
          expect(browser.body).not_to include("We shouldn't see this.")
        end
      end

      it "allows whitelisted urls" do
        browser.intercept_request
        browser.on(:request_intercepted) do |request|
          request.match?(%r{url_whitelist|/wanted}) ? request.continue : request.abort
        end

        browser.goto("/ferrum/url_whitelist")

        expect(browser.status).to eq(200)
        expect(browser.body).to include("We are loading some wanted action here")

        frame = browser.at_xpath("//iframe[@name = 'framename']")
        browser.within_frame(frame) do
          expect(browser.body).to include("We should see this.")
        end

        frame = browser.at_xpath("//iframe[@name = 'unwantedframe']")
        browser.within_frame(frame) do
          expect(browser.body).not_to include("We shouldn't see this.")
        end
      end

      it "supports wildcards" do
        browser.intercept_request
        browser.on(:request_intercepted) do |request|
          request.match?(%r{url_whitelist|/.*wanted}) ? request.continue : request.abort
        end

        browser.goto("/ferrum/url_whitelist")

        expect(browser.status).to eq(200)
        expect(browser.body).to include("We are loading some wanted action here")

        frame = browser.at_xpath("//iframe[@name = 'framename']")
        browser.within_frame(frame) do
          expect(browser.body).to include("We should see this.")
        end

        frame = browser.at_xpath("//iframe[@name = 'unwantedframe']")
        browser.within_frame(frame) do
          expect(browser.body).to include("We shouldn't see this.")
        end
      end
    end
  end
end
