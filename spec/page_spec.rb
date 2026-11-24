# frozen_string_literal: true

describe Ferrum::Page do
  describe "#close" do
    it "closes the page's target" do
      page.go_to
      target_id = page.target_id

      page.close

      wait_for { browser.targets.key?(target_id) }.to be(false)
    end
  end

  describe "#position" do
    it "returns the left and top coordinates of the window" do
      skip if Ferrum::Utils::Platform.mac? && !browser.options.headless

      page.window_bounds = { left: 30, top: 40 }

      expect(page.position).to eq([30, 40])
    end
  end

  describe "#position=" do
    it "allows the window to be positioned" do
      skip if Ferrum::Utils::Platform.mac? && !browser.options.headless

      expect do
        page.position = { left: 10, top: 20 }
      end.to change {
        page.position
      }.to([10, 20])
    end
  end

  describe "#window_bounds=" do
    it "resizes the window" do
      page.window_bounds = { width: 800, height: 600 }

      expect(page.window_bounds).to include("width" => 800, "height" => 600)
    end

    it "changes the window state" do
      page.go_to

      page.window_bounds = { window_state: "fullscreen" }

      expect(page.window_bounds["windowState"]).to eq("fullscreen")
    end
  end

  describe "#window_bounds" do
    it "returns the bounds and state of the window" do
      expect(page.window_bounds).to include(
        "left" => an_instance_of(Integer),
        "top" => an_instance_of(Integer),
        "width" => an_instance_of(Integer),
        "height" => an_instance_of(Integer),
        "windowState" => "normal"
      )
    end
  end

  describe "#window_id" do
    it "returns the same id for pages in the same window" do
      other = browser.create_page

      expect(page.window_id).to be_an(Integer)
      expect(page.window_id).to eq(other.window_id)
    end

    it "returns another id for a page in another context" do
      other = browser.create_page(new_context: true)

      expect(page.window_id).not_to eq(other.window_id)
    end
  end

  describe "#url" do
    it "supports whitespace characters" do
      page.go_to("/arbitrary_path/200/foo%20bar%20baz")

      expect(page.url).to eq(base_url("/arbitrary_path/200/foo%20bar%20baz"))
    end

    it "supports escaped characters" do
      page.go_to("/arbitrary_path/200/foo?a%5Bb%5D=c")

      expect(page.url).to eq(base_url("/arbitrary_path/200/foo?a%5Bb%5D=c"))
    end

    it "supports url in parameter" do
      page.go_to("/arbitrary_path/200/foo%20asd?a=http://example.com/asd%20asd")

      expect(page.url).to eq(base_url("/arbitrary_path/200/foo%20asd?a=http://example.com/asd%20asd"))
    end

    it "supports restricted characters ' []:/+&='" do
      page.go_to("/arbitrary_path/200/foo?a=%20%5B%5D%3A%2F%2B%26%3D")

      expect(page.url).to eq(base_url("/arbitrary_path/200/foo?a=%20%5B%5D%3A%2F%2B%26%3D"))
    end

    it "returns about:blank when on about:blank" do
      page.go_to("about:blank")

      expect(page.url).to eq("about:blank")
    end

    it "handles hash changes" do
      page.go_to("/#omg")
      expect(page.url).to match(%r{/#omg$})
      page.execute <<-JS
        window.onhashchange = function() { window.last_hashchange = window.location.hash }
      JS

      page.go_to("/#foo")

      expect(page.url).to match(%r{/#foo$})
      expect(page.evaluate("window.last_hashchange")).to eq("#foo")
    end
  end

  describe "#wait_until" do
    it "returns the first truthy value of the block" do
      page.go_to("/with_js")
      page.execute("setTimeout(() => window.ready = 'yes', 200)")

      expect(page.wait_until { page.evaluate("window.ready") }).to eq("yes")
    end

    it "returns nil when the block stays falsy" do
      page.go_to("/with_js")

      expect(page.wait_until(timeout: 0.3) { page.evaluate("window.ready") }).to be_nil
    end

    it "returns nil when a call in the block hangs past the timeout" do
      page.go_to("/with_js")
      hang_commands

      expect(page.wait_until(timeout: 0.3) { page.evaluate("window.ready") }).to be_nil
    end
  end

  describe "#wait_until!" do
    it "raises when the block stays falsy" do
      page.go_to("/with_js")

      expect { page.wait_until!(timeout: 0.3) { page.evaluate("window.ready") } }.to raise_error(Ferrum::TimeoutError)
    end
  end

  describe "#bypass_csp=" do
    it "bypasses CSP headers" do
      page.go_to("/csp")
      page.add_script_tag(content: "window.__injected = 42")
      expect(page.evaluate("window.__injected")).to be_nil

      page.bypass_csp = true
      page.refresh
      page.add_script_tag(content: "window.__injected = 42")

      expect(page.evaluate("window.__injected")).to eq(42)
    end

    it "enforces CSP headers again when set to false" do
      page.bypass_csp = true
      page.bypass_csp = false
      page.go_to("/csp")
      page.add_script_tag(content: "window.__injected = 42")

      expect(page.evaluate("window.__injected")).to be_nil
    end
  end

  describe "#evaluate_on_new_document" do
    it "runs JavaScript before the page's scripts" do
      page.evaluate_on_new_document <<~JS
        Object.defineProperty(navigator, "languages", {
          get: function() { return ["tlh"]; }
        });
      JS

      page.go_to("/with_user_js")

      expect(page.at_css("#browser-languages").text).to eq("tlh")
    end

    it "runs JavaScript in the current document too" do
      page.go_to("/simple")

      page.evaluate_on_new_document("window.secret = 'top'", run_immediately: true)

      expect(page.evaluate("window.secret")).to eq("top")
    end
  end

  describe "#remove_script_on_new_document" do
    it "stops running the removed JavaScript in new documents" do
      id = page.evaluate_on_new_document("window.secret = 'top'")
      page.go_to("/simple")
      expect(page.evaluate("window.secret")).to eq("top")

      page.remove_script_on_new_document(id)
      page.refresh

      expect(page.evaluate("window.secret")).to be_nil
    end
  end

  describe "#activate" do
    it "brings the page to the front" do
      page.go_to
      other = browser.create_page
      other.go_to
      other.activate
      wait_for { page.evaluate("document.visibilityState") }.to eq("hidden")

      page.activate

      wait_for { page.evaluate("document.visibilityState") }.to eq("visible")
    end
  end

  describe "#command" do
    it "sends a CDP command and returns its result" do
      result = page.command("Runtime.evaluate", expression: "1 + 1")

      expect(result.dig("result", "value")).to eq(2)
    end

    it "raises when the response doesn't come within timeout:" do
      expect { page.command("Runtime.evaluate", timeout: 0.5, expression: "new Promise(() => {})", awaitPromise: true) }
        .to raise_error(Ferrum::TimeoutError)
    end

    it "rejects the removed wait: instead of sending it to the browser" do
      expect { page.command("Page.navigate", wait: 1, url: base_url("/")) }
        .to raise_error(ArgumentError, "wait: is removed, wrap Page.navigate in await_navigation instead")
    end
  end

  describe "#timeout=" do
    it "supports to change timeout dynamically" do
      page.timeout = 4
      expect { page.go_to!("/really_slow") }.not_to raise_error

      page.timeout = 2
      expect { page.go_to!("/really_slow") }.to raise_error(Ferrum::NavigationTimeoutError)
    end
  end

  describe "#javascript=" do
    it "stops the page's scripts when set to false" do
      page.javascript = false
      page.go_to("/console_log")

      expect(page.evaluate("typeof window.onload")).to eq("object")
    end

    it "runs the page's scripts again after a reload when set back to true" do
      page.javascript = false
      page.go_to("/console_log")
      page.javascript = true
      page.refresh

      expect(page.evaluate("typeof window.onload")).to eq("function")
    end

    it "allows javascript evaluation from Ferrum when set to false" do
      page.javascript = false

      page.evaluate("document.body.innerHTML = '<p>text</p>'")

      expect(page.main_frame.html).to eq("<html><head></head><body><p>text</p></body></html>")
    end
  end

  describe "#javascript?" do
    it "returns true by default" do
      expect(page.javascript?).to be(true)
    end

    it "returns false once javascript is turned off" do
      page.javascript = false

      expect(page.javascript?).to be(false)
    end
  end

  describe "#set_viewport" do
    it "overrides the viewport size" do
      page.set_viewport(width: 500, height: 300, scale_factor: 2)

      expect(page.viewport_size).to eq([500, 300])
      expect(page.device_pixel_ratio).to eq(2)
    end

    def is_mobile?
      page.evaluate("'ontouchstart' in window || navigator.maxTouchPoints > 0")
    end

    it "enables touch/mobile emulation with mobile: true without changing the window size" do
      page.go_to("/")

      expect do
        page.set_viewport(mobile: true)
        page.refresh
      end.to change { is_mobile? }.to(true)
    end

    it "does not enable touch/mobile emulation with mobile: false" do
      page.go_to("/")

      expect do
        page.set_viewport(mobile: false)
        page.refresh
      end.not_to(change { is_mobile? })
    end

    it "keeps the pointer type set with --blink-settings when mobile is not given", :launch do
      browser = Ferrum::Browser.new(browser_options: { "blink-settings" => "primaryPointerType=2,availablePointerTypes=2" })
      browser.go_to(base_url)

      expect do
        browser.set_viewport(width: 500, height: 300)
      end.not_to(change { browser.evaluate("matchMedia('(pointer: coarse)').matches") }.from(true))
    ensure
      browser&.quit
    end

    it "disables touch/mobile emulation with mobile: false after mobile: true" do
      page.go_to("/")
      page.set_viewport(mobile: true)
      page.refresh

      expect do
        page.set_viewport(mobile: false)
        page.refresh
      end.to change { is_mobile? }.from(true).to(false)
    end
  end

  describe "#on" do
    context "with a CDP event" do
      it "subscribes to the event" do
        message = nil

        page.on("Runtime.consoleAPICalled") do |params|
          message = params.dig("args", 0, "value")
        end

        page.evaluate("console.log('hello')")
        wait_for { message }.to eq("hello")
      end

      it "yields only the params" do
        message = nil

        page.on("Runtime.consoleAPICalled", &->(params) { message = params.dig("args", 0, "value") })

        page.evaluate("console.log('hello')")
        wait_for { message }.to eq("hello")
      end
    end

    context "with :request" do
      it "continues the request when given the continue method as a block" do
        network.intercept
        page.on(:request, &:continue)

        page.go_to("/foo")

        expect(page.html).to include("Another World")
      end

      it "skips the remaining callbacks once one handles the request" do
        network.intercept
        later = []
        page.on(:request, &:abort)
        page.on(:request) { |request| later << request.url }

        expect { page.go_to("/foo") }.to raise_error(Ferrum::StatusError)

        expect(later).to be_empty
      end

      it "passes the request to the next callback when one doesn't handle it" do
        network.intercept
        page.on(:request) { |request| request.abort if request.match?(/nothing/) }
        page.on(:request, &:continue)

        page.go_to("/foo")

        expect(page.html).to include("Another World")
      end

      it "continues the request when no callback handles it" do
        network.intercept
        page.on(:request) { |request| request.match?(/nothing/) }

        page.go_to("/foo")

        expect(page.html).to include("Another World")
      end

      it "stops calling a callback once it is unsubscribed" do
        network.intercept
        seen = []
        id = page.on(:request) { |request| seen << request.url }
        page.on(:request, &:continue)

        page.off(:request, id)
        page.go_to("/foo")

        expect(seen).to be_empty
      end
    end

    context "with :response" do
      it "yields the exchange once its response is fully loaded" do
        exchanges = []
        page.on(:response) { |exchange| exchanges << exchange }

        page.go_to("/foo")

        expect(exchanges.size).to eq(1)
        expect(exchanges.first.response.loaded?).to eq(true)
        expect(exchanges.first.response.body).to eq("Another World")
      end

      it "fires once per exchange that finishes loading" do
        exchanges = []
        page.on(:response) { |exchange| exchanges << exchange }

        page.go_to("/with_js")

        expect(exchanges.map(&:url)).to match_array(traffic.map(&:url))
      end

      it "does not fire for requests that fail to load" do
        exchanges = []
        page.on(:response) { |exchange| exchanges << exchange }

        page.go_to("/with_ajax_connection_refused")
        network.wait_idle

        expect(traffic.size).to eq(3)
        expect(exchanges.size).to eq(2)
        expect(exchanges).not_to include(traffic.find(&:error))
      end

      it "does not require request interception to be set up" do
        expect(page.subscribed?("Fetch.requestPaused")).to eq(false)

        exchange = nil
        page.on(:response) { |e| exchange = e }
        page.go_to("/foo")

        expect(exchange).to be
      end
    end

    context "with :console" do
      it "yields new messages" do
        messages = []
        page.on(:console) { |message| messages << message.text }

        page.go_to("/console_log")
        page.execute(%(console.warn("later")))

        wait_for { messages }.to eq(["Hello world", "later"])
      end
    end
  end

  describe "#off" do
    context "with a CDP event" do
      it "unsubscribes a specific event handler" do
        message_a = nil
        message_b = nil

        handler = page.on("Runtime.consoleAPICalled") do |params|
          message_a = params.dig("args", 0, "value")
        end

        page.on("Runtime.consoleAPICalled") do |params|
          message_b = params.dig("args", 0, "value")
        end

        page.evaluate("console.log('hello')")
        wait_for { message_a }.to eq("hello")
        wait_for { message_b }.to eq("hello")

        page.off("Runtime.consoleAPICalled", handler)
        page.evaluate("console.log('goodbye')")

        expect(message_a).to eq("hello")
        wait_for { message_b }.to eq("goodbye")
      end
    end

    context "with :console" do
      it "stops yielding console messages" do
        messages = []
        id = page.on(:console) { |message| messages << message.text }

        page.go_to
        page.execute(%(console.log("first")))
        wait_for { messages }.to eq(["first"])

        page.off(:console, id)
        page.execute(%(console.log("second")))
        wait_for { page.console.size }.to eq(2)

        expect(messages).to eq(["first"])
      end
    end
  end

  describe "#document_node_id" do
    it "returns the node id of the document" do
      page.go_to

      expect(page.document_node_id).to be_a(Integer).and be_positive
    end

    it "returns true when sent asynchronously" do
      page.go_to

      expect(page.document_node_id(async: true)).to be(true)
    end
  end
end
