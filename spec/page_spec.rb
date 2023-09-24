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
        expect { page.go_to("/ferrum/really_slow") }.not_to raise_error
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
        old_timeout = browser.timeout
        browser.timeout = 2
        expect do
          browser.go_to("/ferrum/visit_timeout")
        end.to raise_error(
          Ferrum::PendingConnectionsError,
          %r{Request to http://.*/ferrum/visit_timeout reached server, but there are still pending connections: http://.*/ferrum/really_slow}
        )
      ensure
        browser.timeout = old_timeout
      end

      it "reports pending connection for main frame" do
        prev_timeout = browser.timeout
        browser.timeout = 0.5

        expect do
          browser.go_to("/ferrum/really_slow")
        end.to raise_error(
          Ferrum::PendingConnectionsError,
          %r{Request to http://.*/ferrum/really_slow reached server, but there are still pending connections: http://.*/ferrum/really_slow}
        )
      ensure
        browser.timeout = prev_timeout
      end
    end
  end

  describe "#position=" do
    it "allows the window to be positioned" do
      skip if Ferrum::Utils::Platform.mac? && !browser.headless_new?

      expect do
        page.position = { left: 10, top: 20 }
      end.to change {
        page.position
      }.to([10, 20])
    end
  end

  describe "#current_url" do
    it "supports whitespace characters" do
      page.go_to("/ferrum/arbitrary_path/200/foo%20bar%20baz")

      expect(page.current_url).to eq(base_url("/ferrum/arbitrary_path/200/foo%20bar%20baz"))
    end

    it "supports escaped characters" do
      page.go_to("/ferrum/arbitrary_path/200/foo?a%5Bb%5D=c")

      expect(page.current_url).to eq(base_url("/ferrum/arbitrary_path/200/foo?a%5Bb%5D=c"))
    end

    it "supports url in parameter" do
      page.go_to("/ferrum/arbitrary_path/200/foo%20asd?a=http://example.com/asd%20asd")

      expect(page.current_url).to eq(base_url("/ferrum/arbitrary_path/200/foo%20asd?a=http://example.com/asd%20asd"))
    end

    it "supports restricted characters ' []:/+&='" do
      page.go_to("/ferrum/arbitrary_path/200/foo?a=%20%5B%5D%3A%2F%2B%26%3D")

      expect(page.current_url).to eq(base_url("/ferrum/arbitrary_path/200/foo?a=%20%5B%5D%3A%2F%2B%26%3D"))
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
      page.go_to("/ferrum/auto_refresh")
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
      expect { page.go_to("/ferrum/really_slow") }.not_to raise_error

      page.timeout = 2
      expect { page.go_to("/ferrum/really_slow") }.to raise_error(Ferrum::PendingConnectionsError)
    end
  end

  describe "#disable_javascript" do
    it "disables javascripts on page" do
      page.disable_javascript

      expect { page.go_to("/ferrum/js_error") }.not_to raise_error
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
end
