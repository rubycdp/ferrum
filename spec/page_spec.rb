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
          expect { browser.go_to("/visit_timeout") }.to raise_error(
            Ferrum::PendingConnectionsError,
            %r{Request to http://.*/visit_timeout reached server, but there are still pending connections: http://.*/really_slow}
          )
        end
      end

      it "reports pending connection for main frame" do
        with_timeout(0.5) do
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
      skip if Ferrum::Utils::Platform.mac?

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
      expect(page.body).to include("Visited 0 times")

      page.wait_for_reload(5)

      expect(page.body).to include("Visited 1 times")
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

  describe "#timeout=" do
    it "supports to change timeout dynamically" do
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
  end

  describe "#on" do
    it "subscribes to an event" do
      message = nil

      page.on("Runtime.consoleAPICalled") do |params|
        message = params.dig("args", 0, "value")
      end

      page.evaluate("console.log('hello')")
      wait_a_bit
      expect(message).to eq("hello")
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

  describe "#resize" do
    def body_size
      {
        height: page.evaluate("document.body.clientHeight"),
        width: page.evaluate("document.body.clientWidth")
      }
    end

    def is_mobile?
      page.evaluate("'ontouchstart' in window || navigator.maxTouchPoints > 0")
    end

    before do
      page.go_to("/")
    end

    context "given a different size" do
      it "resizes the page" do
        expect { page.resize(width: 2000, height: 1000) }.to change { body_size }.to(width: 2000, height: 1000)
      end
    end

    context "given a zero height" do
      it "does not change the height" do
        expect { page.resize(width: 2000, height: 0) }.not_to change { body_size[:height] }
      end
    end

    context "given a zero width" do
      it "does not change the width" do
        expect { page.resize(width: 0, height: 1000) }.not_to change { body_size[:width] }
      end
    end

    context "when mobile is true" do
      it "enables mobile emulation in the browser" do
        expect do
          page.resize(width: 0, height: 0, mobile: true)
          page.reload
        end.to change { is_mobile? }.to(true)
      end
    end
  end
end
