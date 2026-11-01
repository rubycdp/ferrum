# frozen_string_literal: true

describe Ferrum::Network::Response do
  describe "#id" do
    it "returns the id of the exchange" do
      page.go_to

      expect(last_exchange.response.id).to eq(last_exchange.id)
    end
  end

  describe "#url" do
    it "returns the url of the response" do
      page.go_to("/with_js")

      expect(last_exchange.response.url).to eq(base_url("/test.js"))
    end

    it "returns the url the request was redirected from for a redirect response" do
      page.go_to("/redirect_again")

      expect(first_exchange.response.url).to eq(base_url("/redirect_again"))
    end
  end
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

  describe "#status_text" do
    it "returns the status text" do
      page.go_to("/status/404")

      expect(first_exchange.response.status_text).to eq("Not Found")
    end
  end

  describe "#headers" do
    it "returns the response headers" do
      page.go_to("/cacheable")

      expect(last_exchange.response.headers).to include("etag" => '"deadbeef"')
    end
  end

  describe "#headers_size" do
    it "returns the number of bytes received for the headers" do
      page.go_to

      expect(last_exchange.response.headers_size).to be_a(Integer).and be_positive
    end
  end

  describe "#type" do
    it "returns the resource type" do
      page.go_to("/with_js")

      expect(traffic.map { |e| e.response.type }).to eq(%w[Document Script Script Script])
    end
  end

  describe "#content_type" do
    it "returns the content type without parameters" do
      page.go_to("/with_js")

      expect(first_exchange.response.headers["content-type"]).to eq("text/html;charset=utf-8")
      expect(first_exchange.response.content_type).to eq("text/html")
    end

    it "returns nil when there is no content type header" do
      page.go_to("/status/204")

      expect(first_exchange.response.content_type).to be_nil
    end
  end

  describe "#body!" do
    it "gets response body" do
      page.go_to("/with_js")
      responses = traffic.map(&:response)

      expect(responses.size).to eq(4)

      expect(responses[0].url).to end_with("/with_js")
      expect(responses[0].body!).to include("ferrum with_js")

      expect(responses[1].url).to end_with("/jquery.min.js")
      expect(responses[1].body!).to include("jQuery v3.7.1")

      expect(responses[2].url).to end_with("/jquery-ui.min.js")
      expect(responses[2].body!).to include("jQuery UI - v1.13.2")

      expect(responses[3].url).to end_with("/test.js")
      expect(responses[3].body!).to include("This is test.js file content")
    end

    it "throws error" do
      page.go_to("/with_js")
      responses = traffic.map(&:response)
      page.go_to("/with_different_resources")

      expect(responses[0].url).to end_with("/with_js")
      expect { responses[0].body! }.to raise_error(Ferrum::BrowserError, "No resource with given identifier found")
    end
  end

  describe "#body" do
    it "gets response body" do
      page.go_to("/with_js")
      responses = traffic.map(&:response)

      expect(responses.size).to eq(4)

      expect(responses[0].url).to end_with("/with_js")
      expect(responses[0].body).to include("ferrum with_js")
    end

    it "throws error" do
      page.go_to("/with_js")
      responses = traffic.map(&:response)
      page.go_to("/with_different_resources")

      expect(responses[0].url).to end_with("/with_js")
      expect(responses[0].body).to be_nil
    end
  end

  describe "#main?" do
    it "returns true for the response of the main document" do
      page.go_to("/with_js")

      expect(first_exchange.response.main?).to be(true)
    end

    it "returns false for the response of a subresource" do
      page.go_to("/with_js")

      expect(last_exchange.response.main?).to be(false)
    end
  end

  describe "#loaded?" do
    it "returns true once the response body is loaded" do
      page.go_to

      expect(last_exchange.response.loaded?).to be(true)
    end

    it "returns falsey before the response body is loaded" do
      response = Ferrum::Network::Response.new(page, { "response" => {} })

      expect(response.loaded?).to be_falsey
    end
  end

  describe "#redirect?" do
    it "returns true for a redirect response" do
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

  describe "#==" do
    it "returns true for responses with the same id" do
      page.go_to

      response = last_exchange.response
      copy = Ferrum::Network::Response.new(page, response.params)

      expect(response).to eq(copy)
    end

    it "returns false for responses with different ids" do
      page.go_to("/with_js")

      expect(first_exchange.response).not_to eq(last_exchange.response)
    end
  end

  describe "#to_h" do
    it "returns #params" do
      page.go_to("/with_js")

      expect(last_exchange.response.to_h).to eq(last_exchange.response.params)
    end
  end
end
