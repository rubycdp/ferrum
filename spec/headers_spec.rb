# frozen_string_literal: true

module Ferrum
  describe Browser do
    context "headers support" do
      it "allows headers to be set" do
        browser.headers.set("Cookie" => "foo=bar", "YourName" => "your_value")
        browser.go_to("/ferrum/headers")
        expect(browser.body).to include("COOKIE: foo=bar")
        expect(browser.body).to include("YOURNAME: your_value")
      end

      it "allows headers to be read" do
        expect(browser.headers.get).to eq({})
        browser.headers.set("User-Agent" => "Browser", "Host" => "foo.com")
        expect(browser.headers.get).to eq("User-Agent" => "Browser", "Host" => "foo.com")
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
          request.open("GET", "/ferrum/headers", false);
          request.send();

          if (request.status === 200) {
            document.body.innerHTML = request.responseText;
          }
        JS
        expect(browser.body).to include("X_OMG: wat")
      end

      it "adds new headers" do
        browser.headers.set("User-Agent" => "Browser", "YourName" => "your_value")
        browser.headers.add({ "User-Agent" => "Super Browser", "Appended" => "true" })
        browser.go_to("/ferrum/headers")
        expect(browser.body).to include("USER_AGENT: Super Browser")
        expect(browser.body).to include("YOURNAME: your_value")
        expect(browser.body).to include("APPENDED: true")
      end

      it "sets accept-language even if user-agent is not provided" do
        browser.headers.add({ "Accept-Language" => "esperanto" })
        browser.go_to("/ferrum/headers")
        expect(browser.body).to include("USER_AGENT: #{browser.default_user_agent}")
        expect(browser.body).to match(/ACCEPT_LANGUAGE: esperanto/)
      end

      it "sets headers on the initial request for referer only" do
        browser.headers.set("PermanentA" => "a")
        browser.headers.add({ "PermanentB" => "b" })
        browser.headers.add({ "Referer" => "http://google.com" }, permanent: false)
        browser.headers.add({ "TempA" => "a" }, permanent: false) # simply ignored

        browser.go_to("/ferrum/headers_with_ajax")
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
        browser.go_to("/ferrum/redirect_to_headers")
        expect(browser.body).to include("X_CUSTOM_HEADER: 1")
      end

      context "multiple windows", skip: true do
        it "persists headers across popup windows" do
          browser.headers.set(
            "Cookie" => "foo=bar",
            "Host" => "foo.com",
            "User-Agent" => "foo"
          )
          browser.go_to("/ferrum/popup_headers")
          browser.at_xpath("//a[text()='pop up']").click

          page, = browser.windows(:last)

          expect(page.body).to include("USER_AGENT: foo")
          expect(page.body).to include("COOKIE: foo=bar")
          expect(page.body).to include("HOST: foo.com")
        end

        it "sets headers in existing windows" do
          page = browser.create_page
          page.headers.set(
            "Cookie" => "foo=bar",
            "Host" => "foo.com",
            "User-Agent" => "foo"
          )
          page.goto("/ferrum/headers")
          expect(page.body).to include("USER_AGENT: foo")
          expect(page.body).to include("COOKIE: foo=bar")
          expect(page.body).to include("HOST: foo.com")

          browser.switch_to_window browser.windows.last
          browser.go_to("/ferrum/headers")
          expect(browser.body).to include("USER_AGENT: foo")
          expect(browser.body).to include("COOKIE: foo=bar")
          expect(browser.body).to include("HOST: foo.com")
        end

        it "keeps temporary headers local to the current window" do
          browser.create_page
          browser.headers.add("X-Custom-Header" => "1", permanent: false)

          browser.switch_to_window browser.windows.last
          browser.go_to("/ferrum/headers")
          expect(browser.body).not_to include("X_CUSTOM_HEADER: 1")

          browser.switch_to_window browser.windows.first
          browser.go_to("/ferrum/headers")
          expect(browser.body).to include("X_CUSTOM_HEADER: 1")
        end

        it "does not mix temporary headers with permanent ones when propagating to other windows" do
          browser.create_page
          browser.headers.add("X-Custom-Header" => "1", permanent: false)
          browser.headers.add("Host" => "foo.com")

          browser.switch_to_window browser.windows.last
          browser.go_to("/ferrum/headers")
          expect(browser.body).to include("HOST: foo.com")
          expect(browser.body).not_to include("X_CUSTOM_HEADER: 1")

          browser.switch_to_window browser.windows.first
          browser.go_to("/ferrum/headers")
          expect(browser.body).to include("HOST: foo.com")
          expect(browser.body).to include("X_CUSTOM_HEADER: 1")
        end

        it "does not propagate temporary headers to new windows" do
          browser.go_to
          browser.headers.add("X-Custom-Header" => "1", permanent: false)
          browser.create_page

          browser.switch_to_window browser.windows.last
          browser.go_to("/ferrum/headers")
          expect(browser.body).not_to include("X_CUSTOM_HEADER: 1")

          browser.switch_to_window browser.windows.first
          browser.go_to("/ferrum/headers")
          expect(browser.body).to include("X_CUSTOM_HEADER: 1")
        end
      end
    end
  end
end
