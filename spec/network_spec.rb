# frozen_string_literal: true

describe Ferrum::Network do
  describe "#traffic" do
    it "keeps track of network traffic" do
      page.go_to("/ferrum/with_js")
      urls = traffic.map { |e| e.request.url }

      expect(urls.size).to eq(4)
      expect(urls.grep(%r{/ferrum/with_js$}).size).to eq(1)
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
      # Due to async nature of browser and the timing of favicon.ico request unpredictability
      # we might get from x to y requests including favicon.ico
      expect(browser.network.traffic.length).to be_between(4, 5)

      browser.restart

      browser.go_to("/ferrum/with_js")
      # Due to async nature of browser and the timing of favicon.ico request unpredictability
      # we might get from x to y requests including favicon.ico
      expect(browser.network.traffic.length).to be_between(4, 5)
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
    network.wait_for_idle

    # Due to async nature of browser and the timing of favicon.ico request unpredictability
    # we might get from x to y requests including favicon.ico
    expect(network.total_connections).to be_between(3, 4)
  end

  it "#finished_connections" do
    expect(network.finished_connections).to eq(0)

    page.go_to("/ferrum/with_ajax_connection_refused")
    network.wait_for_idle

    # Due to async nature of browser and the timing of favicon.ico request unpredictability
    # we might get from x to y requests including favicon.ico
    expect(network.finished_connections).to be_between(3, 4)
  end

  it "#pending_connections" do
    expect(network.pending_connections).to eq(0)

    page.go_to("/ferrum/with_slow_ajax_connection")
    # Due to async nature of browser and the timing of favicon.ico request unpredictability
    # we might get from x to y requests including favicon.ico
    expect(network.pending_connections).to be_between(1, 2)

    network.wait_for_idle
    expect(network.pending_connections).to eq(0)
  end

  it "#request" do
    skip
  end

  it "#response" do
    skip
  end

  it "#status" do
    skip
  end

  describe "#clear" do
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
      expect(last_exchange.response.params.dig("response", "fromDiskCache")).to be_falsey

      page.at_xpath("//a").click
      expect(traffic.length).to eq(2)
      expect(network.status).to eq(200)
      expect(last_exchange.response.params.dig("response", "fromDiskCache")).to be_truthy

      page.network.clear(:cache)
      page.at_xpath("//a").click
      expect(traffic.length).to eq(3)
      expect(network.status).to eq(200)
      expect(last_exchange.response.params.dig("response", "fromDiskCache")).to be_falsey
    end
  end

  describe "#blacklist=" do
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

    it "blocks with array of patterns" do
      network.blacklist = [/unwanted/, /jquery/]

      page.go_to("/ferrum/url_blacklist")

      expect(blocked_urls.size).to eq(4)
      expect(blocked_urls).to include(/unwanted/)
      expect(blocked_urls).to include(/jquery/)
      expect(page.body).to include("Disappearing header")
    end

    it "supports wildcards" do
      network.blacklist = /.*wanted/
      page.go_to("/ferrum/url_whitelist")

      expect(network.status).to eq(200)
      expect(page.body).to include("We are loading some wanted action here")

      frame = page.at_xpath("//iframe[@name = 'framename']").frame
      expect(frame.body).not_to include("We should see this.")

      frame = page.at_xpath("//iframe[@name = 'unwantedframe']").frame
      expect(frame.body).not_to include("We shouldn't see this.")
    end

    it "blocks unwanted iframes" do
      network.blacklist = /unwanted/
      page.go_to("/ferrum/url_blacklist")

      expect(network.status).to eq(200)
      expect(page.body).to include("We are loading some unwanted action here")
      frame = page.at_xpath("//iframe[@name = 'framename']").frame
      expect(frame.body).not_to include("We shouldn't see this.")
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

    it "works with other subscriptions" do
      @intercepted_request = nil

      page.on(:request) do |request, _index, _total|
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

    it "supports multiple pages each with their own blacklist" do
      page_one = browser.create_page
      page_one.network.blacklist = /unwanted/

      page_two = browser.create_page
      page_two.network.blacklist = /jquery/

      page_two.go_to("/ferrum/url_blacklist")
      page_one.go_to("/ferrum/url_blacklist")

      blocked_two = page_two.network.traffic.select(&:blocked?).map { |e| e.request.url }
      expect(blocked_two.size).to eq(1)
      expect(blocked_two).not_to include(/unwanted/)
      expect(blocked_two).to include(/jquery/)
      expect(page_two.body).to include("Disappearing header")

      blocked_one = page_one.network.traffic.select(&:blocked?).map { |e| e.request.url }
      expect(blocked_one.size).to eq(3)
      expect(blocked_one).to include(/unwanted/)
      expect(blocked_one).not_to include(/jquery/)
      expect(page_one.body).not_to include("Disappearing header")
    end
  end

  describe "#whitelist=" do
    let(:blocked_urls) { traffic.select(&:blocked?).map { |e| e.request.url } }

    it "allows all requests when blacklist is not set" do
      network.whitelist = nil

      page.go_to("/ferrum/url_whitelist")

      expect(blocked_urls).to be_empty
      expect(page.body).not_to include("Disappearing header")
    end

    it "blocks with single pattern" do
      network.whitelist = /url_whitelist|jquery/

      page.go_to("/ferrum/url_whitelist")

      expect(blocked_urls.size).to eq(4)
      expect(blocked_urls).to include(/unwanted/)
      expect(blocked_urls).to include(/wanted/)
      expect(page.body).not_to include("Disappearing header")
    end

    it "blocks with array of patterns" do
      network.whitelist = [/url_whitelist/, /unwanted/, /jquery/]

      page.go_to("/ferrum/url_whitelist")

      expect(blocked_urls.size).to eq(3)
      expect(blocked_urls).not_to include(/unwanted/)
      expect(blocked_urls).not_to include(/jquery/)
      expect(page.body).not_to include("Disappearing header")
    end

    it "supports wildcards and frames" do
      network.whitelist = %r{url_whitelist|/.*wanted}
      page.go_to("/ferrum/url_whitelist")

      expect(network.status).to eq(200)
      expect(page.body).to include("We are loading some wanted action here")

      frame = page.at_xpath("//iframe[@name = 'framename']").frame
      expect(frame.body).to include("We should see this.")

      frame = page.at_xpath("//iframe[@name = 'unwantedframe']").frame
      expect(frame.body).to include("We shouldn't see this.")
    end
  end

  describe "#intercept" do
    it "supports :pattern argument" do
      network.intercept(pattern: "*/ferrum/frame_child")
      page.on(:request) do |request|
        request.respond(body: "<h1>hello</h1>")
      end

      page.go_to("/ferrum/frame_parent")

      expect(network.status).to eq(200)
      frame = page.at_xpath("//iframe").frame
      expect(frame.body).to include("hello")
    end

    context "with :resource_type argument" do
      it "raises an error with wrong type" do
        expect { network.intercept(resource_type: :BlaBla) }.to raise_error(ArgumentError)
      end

      it "intercepts only given type" do
        network.intercept(resource_type: :Document)
        page.on(:request) do |request|
          request.respond(body: "<h1>hello</h1>")
        end

        page.go_to("/ferrum/non_existing")

        expect(network.status).to eq(200)
        expect(page.body).to include("hello")
      end
    end

    context "with :request_stage argument" do
      it "raises an error with wrong stage" do
        expect { network.intercept(request_stage: :BlaBla) }.to raise_error(ArgumentError)
      end

      it "intercepts only given stage" do
        network.intercept(request_stage: :Response)
        page.on(:request) do |request|
          request.respond(body: "<h1>hello</h1>")
        end

        page.go_to("/ferrum/index")

        expect(network.status).to eq(200)
        expect(page.body).to include("hello")
      end
    end

    it "supports custom responses" do
      network.intercept
      page.on(:request) do |request|
        request.respond(body: "<h1>custom content that is more than 45 characters</h1>")
      end

      page.go_to("/ferrum/non_existing")

      expect(network.status).to eq(200)
      expect(page.body).to include("custom content that is more than 45 characters")
    end
  end

  describe "#authorize" do
    it "raises error when authorize is without block" do
      expect do
        network.authorize(user: "login", password: "pass")
      end.to raise_exception(ArgumentError,
                             "Block is missing, call `authorize(...) { |r| r.continue } " \
                             "or subscribe to `on(:request)` events before calling it")
    end

    it "raises no error when authorize is with block" do
      expect do
        network.authorize(user: "login", password: "pass") do |request, _index, _total|
          request.continue
        end
      end.not_to raise_error
    end

    it "raises no error when authorize is without block but subscribed to events" do
      expect do
        page.on(:request, &:continue)
        network.authorize(user: "login", password: "pass")
      end.not_to raise_error
    end

    it "denies without credentials" do
      if browser.headless_new?
        expect { page.go_to("/ferrum/basic_auth") }.to raise_error(
          Ferrum::StatusError,
          %r{Request to http://.*/ferrum/basic_auth failed \(net::ERR_INVALID_AUTH_CREDENTIALS\)}
        )
      else
        page.go_to("/ferrum/basic_auth")
      end

      expect(network.status).to eq(401)
      expect(page.body).not_to include("Welcome, authenticated client")
    end

    it "allows with given credentials" do
      network.authorize(user: "login", password: "pass") do |request, _index, _total|
        request.continue
      end

      page.go_to("/ferrum/basic_auth")

      expect(network.status).to eq(200)
      expect(page.body).to include("Welcome, authenticated client")
    end

    it "allows even overwriting headers" do
      network.authorize(user: "login", password: "pass") do |request, _index, _total|
        request.continue
      end
      page.headers.set("Cuprite" => "true")

      page.go_to("/ferrum/basic_auth")

      expect(network.status).to eq(200)
      expect(page.body).to include("Welcome, authenticated client")
    end

    it "denies with wrong credentials" do
      network.authorize(user: "user", password: "pass!") do |request, _index, _total|
        request.continue
      end

      page.go_to("/ferrum/basic_auth")

      expect(network.status).to eq(401)
      expect(page.body).not_to include("Welcome, authenticated client")
    end

    it "allows on POST request" do
      network.authorize(user: "login", password: "pass") do |request, _index, _total|
        request.continue
      end

      page.go_to("/ferrum/basic_auth")
      page.at_css(%([type="submit"])).click

      expect(network.status).to eq(200)
      expect(page.body).to include("Authorized POST request")
    end
  end

  it "#emulate_network_conditions", skip: "doesn't work for now" do
    page.network.emulate_network_conditions(latency: 500)

    start = Ferrum::Utils::ElapsedTime.monotonic_time
    page.go_to("/ferrum/with_js")

    expect(Ferrum::Utils::ElapsedTime.elapsed_time(start)).to eq(2000)
  end

  it "#offline_mode" do
    page.network.offline_mode

    expect { page.go_to("/ferrum/with_js") }.to raise_error(
      Ferrum::StatusError,
      %r{Request to http://.*/ferrum/with_js failed \(net::ERR_INTERNET_DISCONNECTED\)}
    )

    expect(page.at_css("body").text).to match("No internet") if browser.headless_new?
  end
end
