# frozen_string_literal: true

module Ferrum
  describe Network do
    let(:traffic) { browser.network.traffic }

    it "keeps track of network traffic" do
      browser.go_to("/ferrum/with_js")
      urls = traffic.map { |e| e.request.url }

      expect(urls.grep(%r{/ferrum/jquery.min.js$}).size).to eq(1)
      expect(urls.grep(%r{/ferrum/jquery-ui.min.js$}).size).to eq(1)
      expect(urls.grep(%r{/ferrum/test.js$}).size).to eq(1)
    end

    it "gets response body" do
      browser.go_to("/ferrum/with_js")
      responses = traffic.map(&:response)

      expect(responses.size).to eq(4)

      expect(responses[0].url).to end_with("/ferrum/with_js")
      expect(responses[0].body).to include("ferrum with_js")

      expect(responses[1].url).to end_with("/ferrum/jquery.min.js")
      expect(responses[1].body).to include("jQuery v1.11.3")

      expect(responses[2].url).to end_with("/ferrum/jquery-ui.min.js")
      expect(responses[2].body).to include("jQuery UI - v1.11.4")

      expect(responses[3].url).to end_with("/ferrum/test.js")
      expect(responses[3].body).to include("This is test.js file content")
    end

    it "keeps track of blocked network traffic" do
      browser.network.intercept
      browser.on(:request) do |request|
        request.match?(/unwanted/) ? request.abort : request.continue
      end

      browser.go_to("/ferrum/url_blacklist")

      blocked_urls = traffic.select(&:blocked?).map { |e| e.request.url }

      expect(blocked_urls).to include(/unwanted/)
    end

    it "captures responses" do
      browser.go_to("/ferrum/with_js")

      expect(traffic.last.response.status).to eq(200)
    end

    it "captures errors" do
      browser.go_to("/ferrum/with_ajax_fail")
      expect(browser.at_xpath("//h1[text() = 'Done']")).to be

      expect(traffic.last.error).to be
    end

    it "captures refused connection errors" do
      browser.go_to("/ferrum/with_ajax_connection_refused")
      expect(browser.at_xpath("//h1[text() = 'Error']")).to be

      expect(traffic.last.error).to be
      expect(traffic.last.response).to be_nil
      expect(browser.network.idle?).to be true
    end

    it "captures canceled requests" do
      browser.go_to("/ferrum/with_ajax_connection_canceled")

      # FIXME: Hack to wait for content in the browser
      Ferrum.with_attempts(errors: RuntimeError, max: 10, wait: 0.1) do
        browser.at_xpath("//h1[text() = 'Canceled']") || raise("Node not found")
      end

      expect(browser.network.idle?).to be true
    end

    it "keeps a running list between multiple web page views" do
      browser.go_to("/ferrum/with_js")
      expect(traffic.length).to eq(4)

      browser.go_to("/ferrum/with_js")
      expect(traffic.length).to eq(8)
    end

    it "gets cleared on restart" do
      browser.go_to("/ferrum/with_js")
      expect(traffic.length).to eq(4)

      browser.restart

      browser.go_to("/ferrum/with_js")
      expect(traffic.length).to eq(4)
    end

    it "gets cleared when being cleared" do
      browser.go_to("/ferrum/with_js")
      expect(traffic.length).to eq(4)

      browser.network.clear(:traffic)

      expect(traffic.length).to eq(0)
    end

    it "blocked requests get cleared along with network traffic" do
      browser.network.intercept
      browser.on(:request) do |request|
        request.match?(/unwanted/) ? request.abort : request.continue
      end

      browser.go_to("/ferrum/url_blacklist")

      expect(traffic.select(&:blocked?).length).to eq(3)

      browser.network.clear(:traffic)

      expect(traffic.select(&:blocked?).length).to eq(0)
    end

    it "counts network traffic for each loaded resource" do
      browser.go_to("/ferrum/with_js")
      responses = traffic.map(&:response)
      resources_size = {
        %r{/ferrum/jquery.min.js$}    => File.size(PROJECT_ROOT + "/spec/support/public/jquery-1.11.3.min.js"),
        %r{/ferrum/jquery-ui.min.js$} => File.size(PROJECT_ROOT + "/spec/support/public/jquery-ui-1.11.4.min.js"),
        %r{/ferrum/test.js$}          => File.size(PROJECT_ROOT + "/spec/support/public/test.js"),
        %r{/ferrum/with_js$}          => 2343
      }

      resources_size.each do |resource, size|
        expect(responses.find { |r| r.url[resource] }.body_size).to eq(size)
      end
    end

    it "can clear memory cache" do
      browser.network.clear(:cache)

      browser.go_to("/ferrum/cacheable")
      traffic = browser.network.traffic
      expect(traffic.length).to eq(1)
      expect(browser.network.status).to eq(200)
      expect(traffic.last.response.params.dig("response", "fromDiskCache")).to be_falsey

      browser.at_xpath("//a").click
      expect(traffic.length).to eq(2)
      expect(browser.network.status).to eq(200)
      expect(traffic.last.response.params.dig("response", "fromDiskCache")).to be_truthy

      browser.network.clear(:cache)
      browser.at_xpath("//a").click
      expect(traffic.length).to eq(3)
      expect(browser.network.status).to eq(200)
      expect(traffic.last.response.params.dig("response", "fromDiskCache")).to be_falsey
    end

    it "waits for network idle" do
      browser.go_to("/show_cookies")
      expect(browser.body).not_to include("test_cookie")

      browser.at_xpath("//button[text() = 'Set cookie slow']").click
      browser.network.wait_for_idle
      browser.refresh

      expect(browser.body).to include("test_cookie")
    end

    context "status code support" do
      it "determines status from the simple response" do
        browser.go_to("/ferrum/status/500")
        expect(browser.network.status).to eq(500)
      end

      it "determines status code when the page has a few resources" do
        browser.go_to("/ferrum/with_different_resources")
        expect(browser.network.status).to eq(200)
      end

      it "determines status code even after redirect" do
        browser.go_to("/ferrum/redirect")
        expect(browser.network.status).to eq(200)
      end

      it "determines status code when user goes to a page by using a link on it" do
        browser.go_to("/ferrum/with_different_resources")

        browser.at_xpath("//a[text() = 'Go to 500']").click

        expect(browser.network.status).to eq(500)
      end

      it "determines properly status when user goes through a few pages" do
        browser.go_to("/ferrum/with_different_resources")

        browser.at_xpath("//a[text() = 'Go to 200']").click
        browser.at_xpath("//a[text() = 'Go to 201']").click
        browser.at_xpath("//a[text() = 'Do redirect']").click
        browser.at_xpath("//a[text() = 'Go to 402']").click

        expect(browser.network.status).to eq(402)
      end
    end

    context "authentication support" do
      it "raises error when authorize is without block" do
        expect {
          browser.network.authorize(user: "login", password: "pass")
        }.to raise_exception(ArgumentError, "Block is missing, call `authorize(...) { |r| r.continue } or subscribe to `on(:request)` events before calling it")
      end

      it "raises no error when authorize is with block" do
        expect {
          browser.network.authorize(user: "login", password: "pass") { |r| r.continue }
        }.not_to raise_error
      end

      it "raises no error when authorize is without block but subscribed to events" do
        expect {
          browser.on(:request) { |r| r.continue }
          browser.network.authorize(user: "login", password: "pass")
        }.not_to raise_error
      end

      it "denies without credentials" do
        browser.go_to("/ferrum/basic_auth")

        expect(browser.network.status).to eq(401)
        expect(browser.body).not_to include("Welcome, authenticated client")
      end

      it "allows with given credentials" do
        browser.network.authorize(user: "login", password: "pass") do |request|
          request.continue
        end

        browser.go_to("/ferrum/basic_auth")

        expect(browser.network.status).to eq(200)
        expect(browser.body).to include("Welcome, authenticated client")
      end

      it "allows even overwriting headers" do
        browser.network.authorize(user: "login", password: "pass") do |request|
          request.continue
        end
        browser.headers.set("Cuprite" => "true")

        browser.go_to("/ferrum/basic_auth")

        expect(browser.network.status).to eq(200)
        expect(browser.body).to include("Welcome, authenticated client")
      end

      it "denies with wrong credentials" do
        browser.network.authorize(user: "user", password: "pass!") do |request|
          request.continue
        end

        browser.go_to("/ferrum/basic_auth")

        expect(browser.network.status).to eq(401)
        expect(browser.body).not_to include("Welcome, authenticated client")
      end

      it "allows on POST request" do
        browser.network.authorize(user: "login", password: "pass") do |request|
          request.continue
        end

        browser.go_to("/ferrum/basic_auth")
        browser.at_css(%([type="submit"])).click

        expect(browser.network.status).to eq(200)
        expect(browser.body).to include("Authorized POST request")
      end
    end

    context "interception support" do
      it "blocks unwanted urls" do
        browser.network.intercept
        browser.on(:request) do |request|
          request.match?(/unwanted/) ? request.abort : request.continue
        end

        browser.go_to("/ferrum/url_blacklist")

        expect(browser.network.status).to eq(200)
        expect(browser.body).to include("We are loading some unwanted action here")

        frame = browser.at_xpath("//iframe[@name = 'framename']").frame
        expect(frame.body).not_to include("We shouldn't see this.")
      end

      it "supports wildcards" do
        browser.network.intercept
        browser.on(:request) do |request|
          request.match?(/.*wanted/) ? request.abort : request.continue
        end

        browser.go_to("/ferrum/url_whitelist")

        expect(browser.network.status).to eq(200)
        expect(browser.body).to include("We are loading some wanted action here")

        frame = browser.at_xpath("//iframe[@name = 'framename']").frame
        expect(frame.body).not_to include("We should see this.")

        frame = browser.at_xpath("//iframe[@name = 'unwantedframe']").frame
        expect(frame.body).not_to include("We shouldn't see this.")
      end

      it "allows whitelisted urls" do
        browser.network.intercept
        browser.on(:request) do |request|
          request.match?(%r{url_whitelist|/wanted}) ? request.continue : request.abort
        end

        browser.go_to("/ferrum/url_whitelist")

        expect(browser.network.status).to eq(200)
        expect(browser.body).to include("We are loading some wanted action here")

        frame = browser.at_xpath("//iframe[@name = 'framename']").frame
        expect(frame.body).to include("We should see this.")

        frame = browser.at_xpath("//iframe[@name = 'unwantedframe']").frame
        expect(frame.body).not_to include("We shouldn't see this.")
      end

      it "supports wildcards" do
        browser.network.intercept
        browser.on(:request) do |request|
          request.match?(%r{url_whitelist|/.*wanted}) ? request.continue : request.abort
        end

        browser.go_to("/ferrum/url_whitelist")

        expect(browser.network.status).to eq(200)
        expect(browser.body).to include("We are loading some wanted action here")

        frame = browser.at_xpath("//iframe[@name = 'framename']").frame
        expect(frame.body).to include("We should see this.")

        frame = browser.at_xpath("//iframe[@name = 'unwantedframe']").frame
        expect(frame.body).to include("We shouldn't see this.")
      end

      it "supports custom responses" do
        browser.network.intercept
        browser.on(:request) do |request|
          request.respond(body: "<h1>custom content that is more than 45 characters</h1>")
        end

        browser.go_to("/ferrum/non_existing")

        expect(browser.network.status).to eq(200)
        expect(browser.body).to include("content")
      end
    end

    context "supports proxy" do
      let(:options) { Hash.new }
      let(:proxy) { Ferrum::Proxy.start(**options) }

      context "without authorization" do
        it "works without authorization" do
          begin
            browser = Ferrum::Browser.new(
              proxy: { server: { host: proxy.host, port: proxy.port } }
            )

            browser.go_to("https://example.com")
            expect(browser.network.status).to eq(200)
            expect(browser.body).to include("Example Domain")
          ensure
            browser&.quit
          end
        end
      end

      context "with authorization" do
        let(:options) { Hash(user: "user", password: "pa$$") }

        it "works with right password" do
          begin
            browser = Ferrum::Browser.new(
              proxy: { server: { host: proxy.host, port: proxy.port, **options } }
            )

            browser.go_to("https://example.com")
            expect(browser.network.status).to eq(200)
            expect(browser.body).to include("Example Domain")
          ensure
            browser&.quit
          end
        end

        it "breaks with wrong password" do
          begin
            browser = Ferrum::Browser.new(
              proxy: { server: { host: proxy.host, port: proxy.port, user: "u1", password: "p1" } }
            )

            browser.go_to("https://example.com")
            expect(browser.network.status).to eq(407)
          ensure
            browser&.quit
          end
        end
      end

      context "with rotation", skip: "Think how to make it working on CI" do
        it "works after disposing context" do
          begin
            browser = Ferrum::Browser.new(
              proxy: { server: { run: true } }
            )

            browser.proxy_server.rotate(host: "host", port: 0, user: "user", password: "password")
            context = browser.contexts.create
            page = context.create_page
            page.go_to("https://api.ipify.org?format=json")
            expect(page.network.status).to eq(200)
            expect(page.body).to include("x.x.x.x")
            context.dispose

            browser.proxy_server.rotate(host: "host", port: 0, user: "user", password: "password")
            context = browser.contexts.create
            page = context.create_page
            page.go_to("https://api.ipify.org?format=json")
            expect(page.network.status).to eq(200)
            expect(page.body).to include("x.x.x.x")
            context.dispose
          ensure
            browser&.quit
          end
        end
      end
    end
  end
end
