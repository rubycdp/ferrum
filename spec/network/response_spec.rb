# frozen_string_literal: true

describe Ferrum::Network::Response do
  describe "#status" do
    it "captures responses" do
      page.go_to("/with_js")

      expect(last_exchange.response.status).to eq(200)
    end

    it "determines status from the simple response" do
      browser.go_to("/status/500")
      expect(browser.network.status).to eq(500)
    end

    it "determines status code when the page has a few resources" do
      browser.go_to("/with_different_resources")
      expect(browser.network.status).to eq(200)
    end

    it "determines status code even after redirect" do
      browser.go_to("/redirect")
      expect(browser.network.status).to eq(200)
    end

    it "determines status code when user goes to a page by using a link on it" do
      browser.go_to("/with_different_resources")

      browser.at_xpath("//a[text() = 'Go to 500']").click

      expect(browser.network.status).to eq(500)
    end

    it "determines properly status when user goes through a few pages" do
      browser.go_to("/with_different_resources")

      browser.at_xpath("//a[text() = 'Go to 200']").click
      browser.at_xpath("//a[text() = 'Go to 201']").click
      browser.at_xpath("//a[text() = 'Go to 402']").click

      expect(browser.network.status).to eq(402)
    end
  end

  describe "#body" do
    it "gets response body" do
      page.go_to("/with_js")
      responses = traffic.map(&:response)

      expect(responses.size).to eq(4)

      expect(responses[0].url).to end_with("/with_js")
      expect(responses[0].body).to include("ferrum with_js")

      expect(responses[1].url).to end_with("/jquery.min.js")
      expect(responses[1].body).to include("jQuery v3.7.1")

      expect(responses[2].url).to end_with("/jquery-ui.min.js")
      expect(responses[2].body).to include("jQuery UI - v1.13.2")

      expect(responses[3].url).to end_with("/test.js")
      expect(responses[3].body).to include("This is test.js file content")
    end
  end

  describe "#error" do
    it "captures errors" do
      page.go_to("/with_ajax_fail")
      expect(page.at_xpath("//h1[text() = 'Done']")).to be

      expect(last_exchange.error).to be
    end
  end

  describe "#redirect?" do
    it "captures errors" do
      page.go_to("/redirect_again")

      expect(page.body).to include("You landed")
      expect(first_exchange.response.redirect?).to be
    end
  end

  describe "#body_size" do
    it "counts network traffic for each loaded resource" do
      page.go_to("/with_js")
      responses = traffic.map(&:response)
      resources_size = {
        %r{/jquery.min.js$} => File.size("#{PROJECT_ROOT}/spec/support/public/jquery-3.7.1.min.js"),
        %r{/jquery-ui.min.js$} => File.size("#{PROJECT_ROOT}/spec/support/public/jquery-ui-1.13.2.min.js"),
        %r{/test.js$} => File.size("#{PROJECT_ROOT}/spec/support/public/test.js"),
        %r{/with_js$} => 2321
      }

      resources_size.each do |resource, size|
        expect(responses.find { |r| r.url[resource] }.body_size).to eq(size)
      end
    end
  end

  describe "#to_h" do
    it "must return #params" do
      page.go_to("/with_js")

      expect(last_exchange.response.to_h).to eq(last_exchange.response.params)
    end
  end
end
