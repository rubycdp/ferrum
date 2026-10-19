# frozen_string_literal: true

describe Ferrum::Headers do
  describe "#set" do
    it "allows headers to be set" do
      browser.headers.set("Cookie" => "foo=bar", "YourName" => "your_value")
      browser.go_to("/headers")
      expect(browser.body).to include("COOKIE: foo=bar")
      expect(browser.body).to include("YOURNAME: your_value")
    end

    it "supports User-Agent" do
      browser.headers.set("User-Agent" => "foo")
      browser.go_to
      expect(browser.evaluate("window.navigator.userAgent")).to eq("foo")
    end

    it "sets headers for all HTTP requests" do
      browser.headers.set("X-Omg" => "wat")
      browser.go_to
      browser.execute <<-JS
        var request = new XMLHttpRequest();
        request.open("GET", "/headers", false);
        request.send();

        if (request.status === 200) {
          document.body.innerHTML = request.responseText;
        }
      JS
      expect(browser.body).to include("X_OMG: wat")
    end
  end

  describe "#get" do
    it "allows headers to be read" do
      expect(browser.headers.get).to eq({})
      browser.headers.set("User-Agent" => "Browser", "Host" => "foo.com")
      expect(browser.headers.get).to eq("User-Agent" => "Browser", "Host" => "foo.com")
    end
  end

  describe "#add" do
    it "adds new headers" do
      browser.headers.set("User-Agent" => "Browser", "YourName" => "your_value")
      browser.headers.add({ "User-Agent" => "Super Browser", "Appended" => "true" })
      browser.go_to("/headers")
      expect(browser.body).to include("USER_AGENT: Super Browser")
      expect(browser.body).to include("YOURNAME: your_value")
      expect(browser.body).to include("APPENDED: true")
    end

    it "sets Accept-Language even if user-agent is not provided" do
      browser.headers.add({ "Accept-Language" => "esperanto" })
      browser.go_to("/headers")
      expect(browser.body).to include("USER_AGENT: #{browser.default_user_agent}")
      expect(browser.body).to match(/ACCEPT_LANGUAGE: esperanto/)
    end

    it "sets headers on the initial request for referer only" do
      browser.headers.set("PermanentA" => "a")
      browser.headers.add({ "PermanentB" => "b" })
      browser.headers.add({ "Referer" => "http://google.com" }, permanent: false)
      browser.headers.add({ "TempA" => "a" }, permanent: false) # simply ignored

      browser.go_to("/headers_with_ajax")
      initial_request = browser.at_css("#initial_request").text
      ajax_request = browser.at_css("#ajax_request").text

      expect(initial_request).to include("PERMANENTA: a")
      expect(initial_request).to include("PERMANENTB: b")
      expect(initial_request).to include("REFERER: http://google.com")
      expect(initial_request).to include("TEMPA: a")

      expect(ajax_request).to include("PERMANENTA: a")
      expect(ajax_request).to include("PERMANENTB: b")
      expect(ajax_request).to_not include("REFERER: http://google.com")
      expect(ajax_request).to include("TEMPA: a")
    end

    it "keeps added headers on redirects" do
      browser.headers.add({ "X-Custom-Header" => "1" }, permanent: false)
      browser.go_to("/redirect_to_headers")
      expect(browser.body).to include("X_CUSTOM_HEADER: 1")
    end
  end
end
