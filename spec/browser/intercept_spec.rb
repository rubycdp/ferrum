# frozen_string_literal: true

require "spec_helper"

module Ferrum
  describe "intercept requests", skip: true do
    let!(:browser) { Browser.new(base_url: @server.base_url) }

    after { browser.reset }

    context "blacklisting urls for resource requests" do
      it "blocks unwanted urls" do
        browser.url_blacklist = ["unwanted"]

        browser.goto("/ferrum/url_blacklist")

        expect(browser.status).to eq(200)
        expect(browser.body).to include("We are loading some unwanted action here")
        browser.within_frame "framename" do
          expect(browser.body).not_to include("We shouldn't see this.")
        end
      end

      it "supports wildcards" do
        @driver.browser.url_blacklist = ["*wanted"]

        browser "/ferrum/url_whitelist"

        expect(@session.status_code).to eq(200)
        expect(@session).to have_content("We are loading some wanted action here")
        @session.within_frame "framename" do
          expect(@session).not_to have_content("We should see this.")
        end
        @session.within_frame "unwantedframe" do
          expect(@session).not_to have_content("We shouldn't see this.")
        end
      end

      it "can be configured in the driver and survive reset" do
        Capybara.register_driver :cuprite_blacklist do |app|
          Capybara::Cuprite::Driver.new(app, @driver.options.merge(url_blacklist: ["unwanted"]))
        end

        session = Capybara::Session.new(:cuprite_blacklist, @session.app)

        session.visit "/ferrum/url_blacklist"
        expect(session).to have_content("We are loading some unwanted action here")
        session.within_frame "framename" do
          expect(session.html).not_to include("We shouldn't see this.")
        end

        session.reset!

        session.visit "/ferrum/url_blacklist"
        expect(session).to have_content("We are loading some unwanted action here")
        session.within_frame "framename" do
          expect(session.html).not_to include("We shouldn't see this.")
        end
      end
    end

    context "whitelisting urls for resource requests" do
      it "allows whitelisted urls" do
        @driver.browser.url_whitelist = ["url_whitelist", "/wanted"]

        browser "/ferrum/url_whitelist"

        expect(@session.status_code).to eq(200)
        expect(@session).to have_content("We are loading some wanted action here")
        @session.within_frame "framename" do
          expect(@session).to have_content("We should see this.")
        end
        @session.within_frame "unwantedframe" do
          expect(@session).not_to have_content("We shouldn't see this.")
        end
      end

      it "supports wildcards" do
        @driver.browser.url_whitelist = ["url_whitelist", "/*wanted"]

        browser "/ferrum/url_whitelist"

        expect(@session.status_code).to eq(200)
        expect(@session).to have_content("We are loading some wanted action here")
        @session.within_frame "framename" do
          expect(@session).to have_content("We should see this.")
        end
        @session.within_frame "unwantedframe" do
          expect(@session).to have_content("We shouldn't see this.")
        end
      end

      it "blocks overruled urls" do
        @driver.browser.url_whitelist = ["url_whitelist"]
        @driver.browser.url_blacklist = ["url_whitelist"]

        browser "/ferrum/url_whitelist"

        expect(@session.status_code).to eq(nil)
        expect(@session).not_to have_content("We are loading some wanted action here")
      end

      it "allows urls when the whitelist is empty" do
        @driver.browser.url_whitelist = []

        browser "/ferrum/url_whitelist"

        expect(@session.status_code).to eq(200)
        expect(@session).to have_content("We are loading some wanted action here")
        @session.within_frame "framename" do
          expect(@session).to have_content("We should see this.")
        end
      end

      it "can be configured in the driver and survive reset" do
        Capybara.register_driver :cuprite_whitelist do |app|
          Capybara::Cuprite::Driver.new(app, @driver.options.merge(url_whitelist: ["url_whitelist", "/ferrum/wanted"]))
        end

        session = Capybara::Session.new(:cuprite_whitelist, @session.app)

        session.visit "/ferrum/url_whitelist"
        expect(session).to have_content("We are loading some wanted action here")
        session.within_frame "framename" do
          expect(session).to have_content("We should see this.")
        end

        session.within_frame "unwantedframe" do
          # make sure non whitelisted urls are blocked
          expect(session).not_to have_content("We shouldn't see this.")
        end

        session.reset!

        session.visit "/ferrum/url_whitelist"
        expect(session).to have_content("We are loading some wanted action here")
        session.within_frame "framename" do
          expect(session).to have_content("We should see this.")
        end
        session.within_frame "unwantedframe" do
          # make sure non whitelisted urls are blocked
          expect(session).not_to have_content("We shouldn't see this.")
        end
      end
    end
  end
end
