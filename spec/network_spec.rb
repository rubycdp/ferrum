# frozen_string_literal: true

module Ferrum
  describe Network do
    let(:network) { page.network }
    let(:traffic) { network.traffic }

    context "#traffic" do
      it "keeps track of network traffic" do
        page.go_to("/ferrum/with_js")
        urls = traffic.map { |e| e.request.url }

        expect(urls.grep(%r{/ferrum/jquery.min.js$}).size).to eq(1)
        expect(urls.grep(%r{/ferrum/jquery-ui.min.js$}).size).to eq(1)
        expect(urls.grep(%r{/ferrum/test.js$}).size).to eq(1)
      end

      it "keeps a running list between multiple web page views" do
        page.go_to("/ferrum/with_js")
        expect(traffic.length).to eq(4)

        page.go_to("/ferrum/with_js")
        expect(traffic.length).to eq(8)
      end

      it "gets cleared on restart" do
        browser.go_to("/ferrum/with_js")
        expect(browser.network.traffic.length).to eq(4)

        browser.restart

        browser.go_to("/ferrum/with_js")
        expect(browser.network.traffic.length).to eq(4)
      end
    end

    it "#wait_for_idle" do
      page.go_to("/show_cookies")
      expect(page.body).not_to include("test_cookie")

      page.at_xpath("//button[text() = 'Set cookie slow']").click
      network.wait_for_idle
      page.refresh

      expect(page.body).to include("test_cookie")
    end

    it "#idle?" do
      page.go_to("/ferrum/with_slow_ajax_connection")
      expect(page.at_xpath("//h1[text() = 'Slow AJAX']")).to be

      expect(network.idle?).to be_falsey
      network.wait_for_idle
      expect(network.idle?).to be_truthy
    end

    it "#total_connections" do
      expect(network.total_connections).to eq(0)

      page.go_to("/ferrum/with_ajax_connection_refused")

      expect(network.total_connections).to eq(3)
    end

    it "#finished_connections" do
      expect(network.finished_connections).to eq(0)

      page.go_to("/ferrum/with_ajax_connection_refused")

      expect(network.finished_connections).to eq(3)
    end

    it "#pending_connections" do
      expect(network.pending_connections).to eq(0)

      page.go_to("/ferrum/with_slow_ajax_connection")

      expect(network.pending_connections).to eq(1)
      network.wait_for_idle
      expect(network.pending_connections).to eq(0)
    end

    it "#request", skip: true do
    end

    it "#response", skip: true do
    end

    it "#status", skip: true do
    end

    context "#clear" do
      it "raises error when type is not in the list" do
        page.go_to("/ferrum/with_js")
        expect(traffic.length).to eq(4)

        expect { network.clear(:something) }.to raise_error(ArgumentError, ":type should be in [:traffic, :cache]")

        expect(traffic.length).to eq(4)
      end

      it "clears all the traffic" do
        page.go_to("/ferrum/with_js")
        expect(traffic.length).to eq(4)

        page.network.clear(:traffic)

        expect(traffic.length).to eq(0)
      end

      it "clears memory cache" do
        page.network.clear(:cache)

        page.go_to("/ferrum/cacheable")
        expect(traffic.length).to eq(1)
        expect(network.status).to eq(200)
        expect(traffic.last.response.params.dig("response", "fromDiskCache")).to be_falsey

        page.at_xpath("//a").click
        expect(traffic.length).to eq(2)
        expect(network.status).to eq(200)
        expect(traffic.last.response.params.dig("response", "fromDiskCache")).to be_truthy

        page.network.clear(:cache)
        page.at_xpath("//a").click
        expect(traffic.length).to eq(3)
        expect(network.status).to eq(200)
        expect(traffic.last.response.params.dig("response", "fromDiskCache")).to be_falsey
      end
    end

    context "#blacklist=" do
      let(:blocked_urls) { traffic.select(&:blocked?).map { |e| e.request.url } }

      it "allows all requests when blacklist is not set" do
        network.blacklist = nil

        page.go_to("/ferrum/url_blacklist")

        expect(blocked_urls).to be_empty
        expect(page.body).not_to include("Disappearing header")
      end

      it "blocks with single pattern" do
        network.blacklist = /jquery/

        page.go_to("/ferrum/url_blacklist")

        expect(blocked_urls.size).to eq(1)
        expect(blocked_urls).not_to include(/unwanted/)
        expect(blocked_urls).to include(/jquery/)
        expect(page.body).to include("Disappearing header")
      end

      it "blocks unwanted iframes" do
        network.blacklist = /unwanted/
        page.go_to("/ferrum/url_blacklist")

        expect(network.status).to eq(200)
        expect(page.body).to include("We are loading some unwanted action here")
        frame = page.at_xpath("//iframe[@name = 'framename']").frame
        expect(frame.body).not_to include("We shouldn't see this.")
      end

      it "blocks with array of patterns" do
        network.blacklist = [/unwanted/, /jquery/]

        page.go_to("/ferrum/url_blacklist")

        expect(blocked_urls.size).to eq(4)
        expect(blocked_urls).to include(/unwanted/)
        expect(blocked_urls).to include(/jquery/)
        expect(page.body).to include("Disappearing header")
      end

      it "works if set after page is loaded" do
        network.blacklist = nil
        page.go_to("/ferrum/url_blacklist")
        expect(page.body).not_to include("Disappearing header")

        network.blacklist = /jquery/
        network.clear(:traffic)
        page.go_to("/ferrum/url_blacklist")

        expect(blocked_urls.size).to eq(1)
        expect(blocked_urls).to include(/jquery/)
        expect(page.body).to include("Disappearing header")
      end

      it "works with one more subscription" do
        @intercepted_request = nil

        page.on(:request) do |request, index, total|
          @intercepted_request ||= request
        end

        network.blacklist = /jquery/

        page.go_to("/ferrum/url_blacklist")

        expect(@intercepted_request).to be
        expect(@intercepted_request.url).to include("/ferrum/url_blacklist")
      end

      it "gets cleared along with network traffic" do
        network.blacklist = /unwanted/
        page.go_to("/ferrum/url_blacklist")
        expect(traffic.select(&:blocked?).length).to eq(3)

        network.clear(:traffic)

        expect(traffic.select(&:blocked?).length).to eq(0)
      end
    end

    context "#whitelist=" do
      it "supports wildcards" do
        browser.network.blacklist = /.*wanted/
        browser.go_to("/ferrum/url_whitelist")

        expect(browser.network.status).to eq(200)
        expect(browser.body).to include("We are loading some wanted action here")

        frame = browser.at_xpath("//iframe[@name = 'framename']").frame
        expect(frame.body).not_to include("We should see this.")

        frame = browser.at_xpath("//iframe[@name = 'unwantedframe']").frame
        expect(frame.body).not_to include("We shouldn't see this.")
      end

      it "allows whitelisted urls" do
        browser.network.whitelist = %r{url_whitelist|/wanted}
        browser.go_to("/ferrum/url_whitelist")

        expect(browser.network.status).to eq(200)
        expect(browser.body).to include("We are loading some wanted action here")

        frame = browser.at_xpath("//iframe[@name = 'framename']").frame
        expect(frame.body).to include("We should see this.")

        frame = browser.at_xpath("//iframe[@name = 'unwantedframe']").frame
        expect(frame.body).not_to include("We shouldn't see this.")
      end

      it "supports wildcards" do
        browser.network.whitelist = %r{url_whitelist|/.*wanted}
        browser.go_to("/ferrum/url_whitelist")

        expect(browser.network.status).to eq(200)
        expect(browser.body).to include("We are loading some wanted action here")

        frame = browser.at_xpath("//iframe[@name = 'framename']").frame
        expect(frame.body).to include("We should see this.")

        frame = browser.at_xpath("//iframe[@name = 'unwantedframe']").frame
        expect(frame.body).to include("We shouldn't see this.")
      end
    end

    context "#intercept" do
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

    context "#authorize" do
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

    it "captures refused connection errors" do
      page.go_to("/ferrum/with_ajax_connection_refused")
      expect(page.at_xpath("//h1[text() = 'Error']")).to be

      expect(traffic.last.error).to be
      expect(traffic.last.response).to be_nil
      expect(network.idle?).to be true
    end

    it "captures canceled requests" do
      browser.go_to("/ferrum/with_ajax_connection_canceled")

      # FIXME: Hack to wait for content in the browser
      Ferrum.with_attempts(errors: RuntimeError, max: 10, wait: 0.1) do
        browser.at_xpath("//h1[text() = 'Canceled']") || raise("Node not found")
      end

      expect(browser.network.idle?).to be true
    end
  end
end
