# frozen_string_literal: true

describe Ferrum::Page do
  describe "#go_to" do
    let(:port) { server.port }

    context "with success response" do
      it "works when DNS correct" do
        expect { page.go_to("http://localhost:#{port}/") }.not_to raise_error
      end

      it "reports no open resources when there are none" do
        page.timeout = 4
        expect { page.go_to("/really_slow") }.not_to raise_error
      end
    end

    context "with failing response" do
      it "handles navigation error" do
        expect { page.go_to("http://nope:#{port}/") }.to raise_error(
          Ferrum::StatusError,
          %r{Request to http://nope:\d+/ failed \(net::ERR_NAME_NOT_RESOLVED\)}
        )
      end

      it "reports pending connection for image" do
        with_timeout(2) do
          allow(browser.options).to receive(:pending_connection_errors).and_return(true)
          expect { browser.go_to("/visit_timeout") }.to raise_error(
            Ferrum::PendingConnectionsError,
            %r{Request to http://.*/visit_timeout reached server, but there are still pending connections: http://.*/really_slow}
          )
        end
      end

      it "reports pending connection for main frame" do
        with_timeout(0.5) do
          allow(browser.options).to receive(:pending_connection_errors).and_return(true)
          expect { browser.go_to("/really_slow") }.to raise_error(
            Ferrum::PendingConnectionsError,
            %r{Request to http://.*/really_slow reached server, but there are still pending connections: http://.*/really_slow}
          )
        end
      end

      it "handles server error" do
        expect { page.go_to("/server_error") }.to raise_error(
          Ferrum::StatusError,
          %r{Request to http://.*/server_error failed \(net::ERR_HTTP_RESPONSE_CODE_FAILURE\)}
        )

        expect(page.network.status).to eq(500)
        expect(page.network.traffic.first.error.error_text).to eq("net::ERR_HTTP_RESPONSE_CODE_FAILURE")
      end
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

  describe "#current_url" do
    it "supports whitespace characters" do
      page.go_to("/arbitrary_path/200/foo%20bar%20baz")

      expect(page.current_url).to eq(base_url("/arbitrary_path/200/foo%20bar%20baz"))
    end

    it "supports escaped characters" do
      page.go_to("/arbitrary_path/200/foo?a%5Bb%5D=c")

      expect(page.current_url).to eq(base_url("/arbitrary_path/200/foo?a%5Bb%5D=c"))
    end

    it "supports url in parameter" do
      page.go_to("/arbitrary_path/200/foo%20asd?a=http://example.com/asd%20asd")

      expect(page.current_url).to eq(base_url("/arbitrary_path/200/foo%20asd?a=http://example.com/asd%20asd"))
    end

    it "supports restricted characters ' []:/+&='" do
      page.go_to("/arbitrary_path/200/foo?a=%20%5B%5D%3A%2F%2B%26%3D")

      expect(page.current_url).to eq(base_url("/arbitrary_path/200/foo?a=%20%5B%5D%3A%2F%2B%26%3D"))
    end

    it "returns about:blank when on about:blank" do
      page.go_to("about:blank")

      expect(page.current_url).to eq("about:blank")
    end

    it "handles hash changes" do
      page.go_to("/#omg")
      expect(page.current_url).to match(%r{/#omg$})
      page.execute <<-JS
        window.onhashchange = function() { window.last_hashchange = window.location.hash }
      JS

      page.go_to("/#foo")

      expect(page.current_url).to match(%r{/#foo$})
      expect(page.evaluate("window.last_hashchange")).to eq("#foo")
    end
  end

  describe "#back" do
    it "goes back when history state has been pushed" do
      page.go_to

      page.execute(%(window.history.pushState({foo: "bar"}, "title", "bar2.html");))

      expect(page.current_url).to eq(base_url("/bar2.html"))
      expect { page.back }.not_to raise_error
      expect(page.current_url).to eq(base_url("/"))
    end
  end

  describe "#forward" do
    it "goes forward when history state is used" do
      page.go_to

      page.execute(%(window.history.pushState({foo: "bar"}, "title", "bar2.html");))
      expect(page.current_url).to eq(base_url("/bar2.html"))
      # don't use #back here to isolate the test
      page.execute("window.history.go(-1);")

      expect(page.current_url).to eq(base_url("/"))
      expect { page.forward }.not_to raise_error
      expect(page.current_url).to eq(base_url("/bar2.html"))
    end
  end

  describe "#wait_for_reload" do
    it "waits for page to be reloaded" do
      page.go_to("/auto_refresh")
      expect(page.body).to include("Visited 1 times")

      page.wait_for_reload(5)

      expect(page.body).to include("Visited 2 times")
    end
  end

  describe "#wait_for_navigation" do
    before { page.go_to("/") }

    it "waits for a navigation the block starts" do
      navigated = loaded = false
      page.on("Page.frameNavigated") { |params| navigated = params.dig("frame", "url").end_with?("/slow") }
      page.on("Page.loadEventFired") { loaded = navigated }

      expect(page.wait_for_navigation { page.execute("location.href = '/slow'") }).to be(true)
      expect(loaded).to be(true)
      expect(page.body).to include("slow page")
    end

    it "returns after the wait when nothing navigates" do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      expect(page.wait_for_navigation(0.2) { page.execute("1 + 1") }).to be(true)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be_between(0.2, page.timeout)
    end

    it "returns false when the navigation doesn't finish within the page timeout" do
      page.timeout = 1

      expect(page.wait_for_navigation { page.execute("location.href = '/really_slow'") }).to be(false)
    end
  end

  describe "#wait_for_navigation!" do
    before { page.go_to("/") }

    it "waits for a navigation the block starts" do
      navigated = loaded = false
      page.on("Page.frameNavigated") { |params| navigated = params.dig("frame", "url").end_with?("/slow") }
      page.on("Page.loadEventFired") { loaded = navigated }

      page.wait_for_navigation! { page.execute("location.href = '/slow'") }

      expect(loaded).to be(true)
    end

    it "raises when the navigation doesn't finish within the page timeout" do
      page.timeout = 1

      expect { page.wait_for_navigation! { page.execute("location.href = '/really_slow'") } }
        .to raise_error(Ferrum::TimeoutError)
    end
  end

  describe "#bypass_csp" do
    it "can bypass csp headers" do
      page.go_to("/csp")
      page.add_script_tag(content: "window.__injected = 42")
      expect(page.evaluate("window.__injected")).to be_nil

      page.bypass_csp
      page.reload
      page.add_script_tag(content: "window.__injected = 42")

      expect(page.evaluate("window.__injected")).to eq(42)
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

    it "stops running removed JavaScript" do
      id = page.evaluate_on_new_document("window.secret = 'top'")
      page.go_to("/simple")
      expect(page.evaluate("window.secret")).to eq("top")

      page.remove_script_on_new_document(id)
      page.reload

      expect(page.evaluate("window.secret")).to be_nil
    end
  end

  describe "#timeout=" do
    it "supports to change timeout dynamically" do
      allow(browser.options).to receive(:pending_connection_errors).and_return(true)
      page.timeout = 4
      expect { page.go_to("/really_slow") }.not_to raise_error

      page.timeout = 2
      expect { page.go_to("/really_slow") }.to raise_error(Ferrum::PendingConnectionsError)
    end
  end

  describe "#disable_javascript" do
    it "disables javascripts on page" do
      page.disable_javascript

      expect { page.go_to("/js_error") }.not_to raise_error
    end

    it "allows javascript evaluation from Ferrum" do
      page.disable_javascript

      page.evaluate("document.body.innerHTML = '<p>text</p>'")

      expect(page.main_frame.body).to eq("<html><head></head><body><p>text</p></body></html>")
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

    context "when mobile is true" do
      it "enables touch/mobile emulation without changing the window size" do
        page.go_to("/")

        expect do
          page.set_viewport(mobile: true)
          page.reload
        end.to change { is_mobile? }.to(true)
      end
    end

    context "when mobile is false" do
      it "does not enable touch/mobile emulation" do
        page.go_to("/")

        expect do
          page.set_viewport(mobile: false)
          page.reload
        end.not_to(change { is_mobile? })
      end
    end

    context "when mobile is not given" do
      it "keeps the pointer type set with --blink-settings", :launch do
        browser = Ferrum::Browser.new(browser_options: { "blink-settings" => "primaryPointerType=2,availablePointerTypes=2" })
        browser.go_to(base_url)

        expect do
          browser.set_viewport(width: 500, height: 300)
        end.not_to(change { browser.evaluate("matchMedia('(pointer: coarse)').matches") }.from(true))
      ensure
        browser&.quit
      end
    end

    context "when mobile was true before" do
      it "disables touch/mobile emulation again" do
        page.go_to("/")
        page.set_viewport(mobile: true)
        page.reload

        expect do
          page.set_viewport(mobile: false)
          page.reload
        end.to change { is_mobile? }.from(true).to(false)
      end
    end
  end

  describe "#on" do
    it "subscribes to an event" do
      message = nil

      page.on("Runtime.consoleAPICalled") do |params|
        message = params.dig("args", 0, "value")
      end

      page.evaluate("console.log('hello')")
      wait_for { message }.to eq("hello")
    end
  end

  describe "#off" do
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
end
