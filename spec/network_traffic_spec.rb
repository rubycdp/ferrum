# frozen_string_literal: true

require "spec_helper"

module Ferrum
  describe Browser do
    context "network traffic support" do
      it "keeps track of network traffic" do
        browser.goto("/ferrum/with_js")
        urls = browser.network_traffic.map(&:url)

        expect(urls.grep(%r{/ferrum/jquery.min.js$}).size).to eq(1)
        expect(urls.grep(%r{/ferrum/jquery-ui.min.js$}).size).to eq(1)
        expect(urls.grep(%r{/ferrum/test.js$}).size).to eq(1)
      end

      it "keeps track of blocked network traffic" do
        browser.intercept_request
        browser.on(:request_intercepted) do |request|
          request.match?(/unwanted/) ? request.abort : request.continue
        end

        browser.goto("/ferrum/url_blacklist")

        blocked_urls = browser.network_traffic(:blocked).map(&:url)

        expect(blocked_urls).to include(/unwanted/)
      end

      it "captures responses" do
        browser.goto("/ferrum/with_js")
        request = browser.network_traffic.last

        expect(request.response.status).to eq(200)
      end

      it "captures errors" do
        browser.goto("/ferrum/with_ajax_fail")
        expect(browser.at_xpath("//h1[text() = 'Done']")).to be

        error = browser.network_traffic.last.error
        expect(error).to be
      end

      it "keeps a running list between multiple web page views" do
        browser.goto("/ferrum/with_js")
        expect(browser.network_traffic.length).to eq(4)

        browser.goto("/ferrum/with_js")
        expect(browser.network_traffic.length).to eq(8)
      end

      it "gets cleared on restart" do
        browser.goto("/ferrum/with_js")
        expect(browser.network_traffic.length).to eq(4)

        browser.restart

        browser.goto("/ferrum/with_js")
        expect(browser.network_traffic.length).to eq(4)
      end

      it "gets cleared when being cleared" do
        browser.goto("/ferrum/with_js")
        expect(browser.network_traffic.length).to eq(4)

        browser.clear_network_traffic

        expect(browser.network_traffic.length).to eq(0)
      end

      it "blocked requests get cleared along with network traffic" do
        browser.intercept_request
        browser.on(:request_intercepted) do |request|
          request.match?(/unwanted/) ? request.abort : request.continue
        end

        browser.goto("/ferrum/url_blacklist")

        expect(browser.network_traffic(:blocked).length).to eq(3)

        browser.clear_network_traffic

        expect(browser.network_traffic(:blocked).length).to eq(0)
      end

      it "counts network traffic for each loaded resource" do
        browser.goto("/ferrum/with_js")
        responses = browser.network_traffic.map(&:response)
        resources_size = {
          %r{/ferrum/jquery.min.js$}    => File.size(PROJECT_ROOT + "/spec/support/public/jquery-1.11.3.min.js"),
          %r{/ferrum/jquery-ui.min.js$} => File.size(PROJECT_ROOT + "/spec/support/public/jquery-ui-1.11.4.min.js"),
          %r{/ferrum/test.js$}          => File.size(PROJECT_ROOT + "/spec/support/public/test.js"),
          %r{/ferrum/with_js$}          => 2325
        }

        resources_size.each do |resource, size|
          expect(responses.find { |r| r.url[resource] }.body_size).to eq(size)
        end
      end
    end
  end
end
