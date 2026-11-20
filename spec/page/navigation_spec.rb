# frozen_string_literal: true

describe Ferrum::Page::Navigation do
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

      it "does not block on a lazy iframe" do
        expect { page.go_to("/lazy_iframe") }.not_to raise_error

        states = page.frames.reject(&:main?).map(&:state)
        expect(states).to eq(%i[stopped_loading stopped_loading])
      end

      it "loads in-viewport lazy iframes" do
        page.go_to("/lazy_iframe")
        frame = page.frame_by(name: "lazy_in_viewport")

        states = page.frames.reject(&:main?).map(&:state)
        expect(frame.body).to include("slow page")
        expect(states).to eq(%i[stopped_loading stopped_loading])
      end

      it "sends the given referrer with the navigation and not with later requests" do
        page.go_to("/headers_with_ajax", referrer: "http://google.com/")

        expect(page.at_css("#initial_request").text).to include("REFERER: http://google.com/")
        expect(page.at_css("#ajax_request").text).not_to include("REFERER: http://google.com/")
        expect(page.evaluate("document.referrer")).to eq("http://google.com/")
      end

      it "sends the given referrer for that navigation only" do
        page.go_to("/headers", referrer: "http://google.com/")
        page.go_to("/headers")

        expect(page.body).not_to include("REFERER: http://google.com/")
      end
    end

    context "with failing response" do
      it "handles navigation error" do
        expect { page.go_to("http://nope:#{port}/") }.to raise_error(
          Ferrum::StatusError,
          %r{Request to http://nope:\d+/ failed \(net::ERR_NAME_NOT_RESOLVED\)}
        )
      end

      it "returns nil when the page doesn't load in time" do
        expect(page.go_to("/really_slow", timeout: 0.5)).to be_nil
      end

      it "raises once the surrounding Deadline.within block runs out" do
        Ferrum::Deadline.within(0.5) do
          expect { page.go_to("/really_slow") }.to raise_error(Ferrum::NavigationTimeoutError)
          expect { page.go_to("/") }.to raise_error(Ferrum::NavigationTimeoutError)
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

  describe "#go_to!" do
    it "reports pending connection for image" do
      with_timeout(2) do
        expect { browser.go_to!("/visit_timeout") }.to raise_error(
          Ferrum::NavigationTimeoutError,
          %r{Timed out waiting for http://.*/visit_timeout to load, still pending: http://.*/really_slow\.}
        )
      end
    end

    it "reports pending connection for main frame" do
      with_timeout(0.5) do
        expect { browser.go_to!("/really_slow") }.to raise_error(
          Ferrum::NavigationTimeoutError,
          %r{Timed out waiting for http://.*/really_slow to load, still pending: http://.*/really_slow\.}
        )
      end
    end

    it "bounds the navigation by the given timeout instead of the page timeout" do
      started = Ferrum::Utils::ElapsedTime.monotonic_time

      expect { page.go_to!("/really_slow", timeout: 0.5) }
        .to raise_error(Ferrum::NavigationTimeoutError)
      expect(Ferrum::Utils::ElapsedTime.elapsed_time(started)).to be < 2
    end

    it "is bound by the surrounding Deadline.within block" do
      started = Ferrum::Utils::ElapsedTime.monotonic_time

      Ferrum::Deadline.within(0.5) do
        expect { page.go_to!("/really_slow") }.to raise_error(Ferrum::NavigationTimeoutError)
      end
      expect(Ferrum::Utils::ElapsedTime.elapsed_time(started)).to be < 2
    end

    it "returns the frame id when the page loads" do
      expect(page.go_to!("/")).to eq(page.main_frame.id)
    end
  end

  describe "#refresh" do
    it "reloads the page and waits for it to load" do
      page.go_to("/slow")
      page.execute("window.marker = 'set'")

      expect(page.refresh).to be(true)

      expect(page.evaluate("window.marker")).to be_nil
      expect(page.body).to include("slow page")
    end

    it "returns nil when the given timeout is already used up" do
      page.go_to("/slow")

      expect(page.refresh(timeout: 0)).to be_nil
    end
  end

  describe "#refresh!" do
    it "reloads the page" do
      page.go_to("/slow")

      expect(page.refresh!).to be(true)
    end

    it "raises when the page doesn't load in time" do
      page.go_to("/visit_timeout", timeout: 0.5)

      expect { page.refresh!(timeout: 0.5) }.to raise_error(Ferrum::NavigationTimeoutError, /still pending/)
    end
  end

  describe "#stop" do
    it "stops the pending navigation" do
      page.go_to("/simple")
      page.execute("location.href = '/really_slow'")

      page.stop

      expect(page.url).to eq(base_url("/simple"))
      expect(page.at_css("title").text).to eq("Test")
    end
  end

  describe "#back" do
    it "returns nil when the history query and the navigation take longer than the timeout together" do
      page.go_to("/simple")
      page.go_to("/with_js")

      with_timeout(0.5) do
        slow_commands(0.3)
        expect(page.back).to be_nil
      end
    end

    it "lets the given timeout exceed the page timeout" do
      page.go_to("/simple")
      page.go_to("/with_js")

      with_timeout(0.5) do
        slow_commands(0.3)
        expect(page.back(timeout: 5)).to be(true)
      end
    end

    it "goes back when history state has been pushed" do
      page.go_to

      page.execute(%(window.history.pushState({foo: "bar"}, "title", "bar2.html");))

      expect(page.url).to eq(base_url("/bar2.html"))
      expect(page.back).to be(true)
      expect(page.url).to eq(base_url("/"))
    end

    it "returns nil when there's no previous page" do
      expect(page.back).to be_nil
    end
  end

  describe "#back!" do
    it "raises when the history query and the navigation take longer than the given timeout" do
      page.go_to("/simple")
      page.go_to("/with_js")

      slow_commands(0.3)

      expect { page.back!(timeout: 0.5) }.to raise_error(Ferrum::TimeoutError)
    end

    it "goes back to the previous page" do
      page.go_to("/simple")
      page.go_to("/with_js")

      expect(page.back!).to be(true)
      expect(page.url).to eq(base_url("/simple"))
    end
  end

  describe "#forward" do
    it "returns nil when the history query and the navigation take longer than the given timeout" do
      page.go_to("/simple")
      page.go_to("/with_js")
      page.back

      slow_commands(0.3)

      expect(page.forward(timeout: 0.5)).to be_nil
    end

    it "goes forward when history state is used" do
      page.go_to

      page.execute(%(window.history.pushState({foo: "bar"}, "title", "bar2.html");))
      expect(page.url).to eq(base_url("/bar2.html"))
      page.execute("window.history.go(-1);")

      expect(page.url).to eq(base_url("/"))
      expect(page.forward).to be(true)
      expect(page.url).to eq(base_url("/bar2.html"))
    end
  end

  describe "#forward!" do
    it "raises when the history query and the navigation take longer than the given timeout" do
      page.go_to("/simple")
      page.go_to("/with_js")
      page.back

      slow_commands(0.3)

      expect { page.forward!(timeout: 0.5) }.to raise_error(Ferrum::TimeoutError)
    end
  end

  describe "#await_navigation" do
    before { page.go_to("/") }

    it "waits for a navigation the block starts" do
      navigated = loaded = false
      page.on("Page.frameNavigated") { |params| navigated = params.dig("frame", "url").end_with?("/slow") }
      page.on("Page.loadEventFired") { loaded = navigated }

      expect(page.await_navigation { page.execute("location.href = '/slow'") }).to be(true)
      expect(loaded).to be(true)
      expect(page.body).to include("slow page")
    end

    it "returns nil when nothing navigates" do
      expect(page.await_navigation(timeout: 0.3) { page.execute("1 + 1") }).to be_nil
      expect(page.idle).to be_set
    end

    it "returns true after watching when nothing navigates" do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      expect(page.await_navigation(watch: 0.2) { page.execute("1 + 1") }).to be(true)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be_between(0.2, page.timeout)
      expect(page.idle).to be_set
    end

    it "waits for a navigation that begins while watching" do
      expect(page.await_navigation(watch: 0.5) { page.execute("setTimeout(() => location.href = '/slow', 50)") })
        .to be(true)
      expect(page.body).to include("slow page")
    end

    it "returns nil when the navigation doesn't finish within the page timeout" do
      page.timeout = 1

      expect(page.await_navigation { page.execute("location.href = '/really_slow'") }).to be_nil
    end

    it "returns nil when the navigation doesn't finish within the given timeout" do
      expect(page.await_navigation(timeout: 0.5) { page.execute("location.href = '/really_slow'") }).to be_nil
    end

    it "raises without a block" do
      expect { page.await_navigation }.to raise_error(ArgumentError, /needs a block/)
    end
  end

  describe "#await_navigation!" do
    before { page.go_to("/") }

    it "waits for a navigation the block starts" do
      expect(page.await_navigation! { page.execute("location.href = '/slow'") }).to be(true)
      expect(page.body).to include("slow page")
    end

    it "raises when the navigation doesn't finish within the page timeout" do
      page.timeout = 1

      expect { page.await_navigation! { page.execute("location.href = '/really_slow'") } }
        .to raise_error(Ferrum::TimeoutError)
    end
  end

  describe "#wait_for_reload" do
    it "waits for page to be reloaded and warns that it is deprecated" do
      page.go_to("/auto_refresh")
      expect(page.body).to include("Visited 1 times")
      Ferrum::Utils::Deprecate.reset!

      expect { page.wait_for_reload(5) }
        .to output(/wait_for_reload will be removed in Ferrum 0\.22.*called from #{__FILE__}/m).to_stderr
      expect(page.body).to include("Visited 2 times")
    end
  end

  describe "#wait_for_navigation" do
    before do
      page.go_to("/")
      Ferrum::Utils::Deprecate.reset!
    end

    it "waits for a navigation the block starts and warns that it is deprecated" do
      expect { expect(page.wait_for_navigation(0.2) { page.execute("location.href = '/slow'") }).to be(true) }
        .to output(/wait_for_navigation will be removed in Ferrum 0\.22.*called from #{__FILE__}/m).to_stderr
      expect(page.body).to include("slow page")
    end

    it "returns false when the navigation doesn't finish in time" do
      result = nil

      expect { result = page.wait_for_navigation(timeout: 0.5) { page.execute("location.href = '/really_slow'") } }
        .to output(/wait_for_navigation will be removed/).to_stderr
      expect(result).to be(false)
    end
  end

  describe "#wait_for_navigation!" do
    it "raises when the navigation doesn't finish in time" do
      page.go_to("/")
      allow(Ferrum::Utils::Deprecate).to receive(:warn)

      expect { page.wait_for_navigation!(timeout: 0.5) { page.execute("location.href = '/really_slow'") } }
        .to raise_error(Ferrum::TimeoutError)
    end
  end
end
