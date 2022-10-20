# frozen_string_literal: true

describe Ferrum::Page do
  describe "#go_to" do
    let(:port) { server.port }

    context "with success response" do
      it "works when DNS correct" do
        expect { browser.go_to("http://localhost:#{port}/") }.not_to raise_error
      end

      it "reports no open resources when there are none" do
        old_timeout = browser.timeout
        browser.timeout = 4
        expect { browser.go_to("/ferrum/really_slow") }.not_to raise_error
      ensure
        browser.timeout = old_timeout
      end
    end

    context "with failing response" do
      it "handles when a non-existent file was specified" do
        file_name = "file:non-existent"

        expect do
          page.go_to(file_name)
        end.to raise_error(
          Ferrum::StatusError,
          "Request to #{file_name} failed to reach server, check DNS and server status"
        )
      end

      it "handles when DNS is incorrect" do
        expect { browser.go_to("http://nope:#{port}/") }.to raise_error(
          Ferrum::StatusError,
          %r{Request to http://nope:\d+/ failed to reach server, check DNS and server status}
        )
      end

      it "has a descriptive message when DNS incorrect" do
        url = "http://nope:#{port}/"

        expect do
          browser.go_to(url)
        end.to raise_error(
          Ferrum::StatusError,
          /Request to #{url} failed to reach server, check DNS and server status/
        )
      end

      it "reports open resource requests" do
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

      it "reports open resource requests for main frame" do
        prev_timeout = browser.timeout
        browser.timeout = 0.1

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
    it "allows the window to be positioned", if: !Ferrum::Utils::Platform.mac? do
      expect do
        browser.position = { left: 10, top: 20 }
      end.to change {
        browser.position
      }.from([0, 0]).to([10, 20])
    end
  end

  describe "#current_url" do
    it "supports whitespace characters" do
      browser.go_to("/ferrum/arbitrary_path/200/foo%20bar%20baz")
      expect(browser.current_url).to eq(base_url("/ferrum/arbitrary_path/200/foo%20bar%20baz"))
    end

    it "supports escaped characters" do
      browser.go_to("/ferrum/arbitrary_path/200/foo?a%5Bb%5D=c")
      expect(browser.current_url).to eq(base_url("/ferrum/arbitrary_path/200/foo?a%5Bb%5D=c"))
    end

    it "supports url in parameter" do
      browser.go_to("/ferrum/arbitrary_path/200/foo%20asd?a=http://example.com/asd%20asd")
      expect(browser.current_url).to eq(base_url("/ferrum/arbitrary_path/200/foo%20asd?a=http://example.com/asd%20asd"))
    end

    it "supports restricted characters ' []:/+&='" do
      browser.go_to("/ferrum/arbitrary_path/200/foo?a=%20%5B%5D%3A%2F%2B%26%3D")
      expect(browser.current_url).to eq(base_url("/ferrum/arbitrary_path/200/foo?a=%20%5B%5D%3A%2F%2B%26%3D"))
    end

    it "returns about:blank when on about:blank" do
      browser.go_to("about:blank")
      expect(browser.current_url).to eq("about:blank")
    end

    it "handles hash changes" do
      browser.go_to("/#omg")
      expect(browser.current_url).to match(%r{/#omg$})
      browser.execute <<-JS
        window.onhashchange = function() { window.last_hashchange = window.location.hash }
      JS

      browser.go_to("/#foo")

      expect(browser.current_url).to match(%r{/#foo$})
      expect(browser.evaluate("window.last_hashchange")).to eq("#foo")
    end
  end

  describe "#back" do
    it "goes back when history state has been pushed" do
      browser.go_to
      browser.execute(%(window.history.pushState({foo: "bar"}, "title", "bar2.html");))
      expect(browser.current_url).to eq(base_url("/bar2.html"))
      expect { browser.back }.not_to raise_error
      expect(browser.current_url).to eq(base_url("/"))
    end
  end

  describe "#forward" do
    it "goes forward when history state is used" do
      browser.go_to
      browser.execute(%(window.history.pushState({foo: "bar"}, "title", "bar2.html");))
      expect(browser.current_url).to eq(base_url("/bar2.html"))
      # don't use #back here to isolate the test
      browser.execute("window.history.go(-1);")
      expect(browser.current_url).to eq(base_url("/"))
      expect { browser.forward }.not_to raise_error
      expect(browser.current_url).to eq(base_url("/bar2.html"))
    end
  end

  describe "#wait_for_reload" do
    it "waits for page to be reloaded" do
      browser.go_to("/ferrum/auto_refresh")
      expect(browser.body).to include("Visited 0 times")

      browser.wait_for_reload(5)

      expect(browser.body).to include("Visited 1 times")
    end
  end

  describe "#bypass_csp" do
    it "can bypass csp headers" do
      browser.go_to("/csp")
      browser.add_script_tag(content: "window.__injected = 42")
      expect(browser.evaluate("window.__injected")).to be_nil

      browser.bypass_csp
      browser.reload
      browser.add_script_tag(content: "window.__injected = 42")

      expect(browser.evaluate("window.__injected")).to eq(42)
    end
  end
end
