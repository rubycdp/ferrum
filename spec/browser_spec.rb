# frozen_string_literal: true

module Ferrum
  describe Browser do
    it "supports a custom path" do
      begin
        original_path = "#{PROJECT_ROOT}/spec/support/chrome_path"
        File.write(original_path, browser.process.path)

        file = "#{PROJECT_ROOT}/spec/support/custom_chrome_called"
        path = "#{PROJECT_ROOT}/spec/support/custom_chrome"

        browser = Browser.new(browser_path: path)

        # If the correct custom path is called, it will touch the file.
        # We allow at least 10 secs for this to happen before failing.

        tries = 0
        until File.exist?(file) || tries == 100
          sleep 0.1
          tries += 1
        end

        expect(File.exist?(file)).to be true
      ensure
        FileUtils.rm_f(original_path)
        FileUtils.rm_f(file)
        browser&.quit
      end
    end

    context "output redirection" do
      let(:logger) { StringIO.new }

      it "supports capturing console.log" do
        begin
          browser = Browser.new(logger: logger)
          browser.go_to(base_url("/ferrum/console_log"))
          expect(logger.string).to include("Hello world")
        ensure
          browser&.quit
        end
      end
    end

    it "ignores default options" do
      begin
        defaults = Browser::Options::Chrome.options.except("disable-web-security")
        browser = Browser.new(ignore_default_browser_options: true, browser_options: defaults)
        browser.go_to(base_url("/ferrum/console_log"))
      ensure
        browser&.quit
      end
    end

    it "raises an error when browser is too slow" do
      path = "#{PROJECT_ROOT}/spec/support/no_chrome"

      expect {
        Browser.new(browser_path: path, process_timeout: 2)
      }.to raise_error(
        Ferrum::ProcessTimeoutError,
        "Browser did not produce websocket url within 2 seconds, try to increase `:process_timeout`. See https://github.com/rubycdp/ferrum#customization"
      )
    end

    it "includes the process output in the error" do
      path = "#{PROJECT_ROOT}/spec/support/broken_chrome"

      expect {
        Browser.new(browser_path: path)
      }.to raise_error(Ferrum::ProcessTimeoutError) do |ex|
        expect(ex.output).to include "Broken Chrome error message"
      end
    end

    it "raises an error and restarts the client if the client dies while executing a command" do
      expect { browser.crash }.to raise_error(Ferrum::DeadBrowserError)
      browser.go_to
      expect(browser.body).to include("Hello world")
    end

    it "stops silently before goto call" do
      browser = Browser.new
      expect { browser.quit }.not_to raise_error
    end

    it "has a viewport size of 1024x768 by default" do
      browser.go_to

      expect(browser.viewport_size).to eq([1024, 768])
    end

    it "allows the viewport to be resized" do
      browser.go_to
      browser.resize(width: 200, height: 400)
      expect(browser.viewport_size).to eq([200, 400])
    end

    context "fullscreen" do
      shared_examples "resize viewport by fullscreen" do
        it "allows the viewport to be resized by fullscreen" do
          expect(browser.viewport_size).to eq([1024, 768])
          browser.go_to(path)
          browser.resize(fullscreen: true)
          expect(browser.viewport_size).to eq(viewport_size)
        end
      end

      include_examples "resize viewport by fullscreen" do
        let(:path) { "/ferrum/custom_html_size" }
        let(:viewport_size) { [1280, 1024] }
      end

      include_examples "resize viewport by fullscreen" do
        let(:path) { "/ferrum/custom_html_size_100%" }
        let(:viewport_size) { [1272, 1008] }
      end

      it "resizes to 'normal' from 'fullscreen' window state" do
        browser.go_to(path)
        browser.resize(fullscreen: true)
        browser.resize(width: 200, height: 400)
        expect(browser.viewport_size).to eq([200, 400])
      end
    end

    it "allows the window to be positioned" do
      left, top = browser.position
      browser.position = { left: left + 10, top: top + 20 }
      expect(browser.position).to eq([left + 10, top + 20])
    end

    it "allows the page to be scrolled" do
      browser.go_to("/ferrum/long_page")
      browser.resize(width: 10, height: 10)
      browser.mouse.scroll_to(200, 100)
      expect(
        browser.evaluate("[window.scrollX, window.scrollY]")
      ).to eq([200, 100])
    end

    it "supports specifying viewport size with an option" do
      begin
        browser = Browser.new(window_size: [800, 600])
        browser.go_to(base_url)
        expect(browser.viewport_size).to eq([800, 600])
      ensure
        browser&.quit
      end
    end

    it "supports clicking precise coordinates" do
      browser.go_to("/ferrum/click_coordinates")
      browser.mouse.click(x: 100, y: 150)
      expect(browser.body).to include("x: 100, y: 150")
    end

    it "supports stopping the session", skip: Ferrum.windows? do
      browser = Browser.new
      pid = browser.process.pid

      expect(Process.kill(0, pid)).to eq(1)
      browser.quit

      expect { Process.kill(0, pid) }.to raise_error(Errno::ESRCH)
    end

    context "extending browser javascript" do
      it "supports extending the browser's world with files" do
        begin
          browser = Browser.new(base_url: base_url,
                                extensions: [File.expand_path("support/geolocation.js", __dir__)])

          browser.go_to("/ferrum/requiring_custom_extension")

          expect(
            browser.body
          ).to include(%(Location: <span id="location">1,-1</span>))

          expect(
            browser.evaluate(%(document.getElementById("location").innerHTML))
          ).to eq("1,-1")

          expect(
            browser.evaluate("navigator.geolocation")
          ).to_not eq(nil)
        ensure
          browser&.quit
        end
      end

      it "supports extending the browser's world with source" do
        begin
          browser = Browser.new(base_url: base_url,
                                extensions: [{source: "window.secret = 'top'"}])

          browser.go_to("/ferrum/requiring_custom_extension")

          expect(browser.evaluate(%(window.secret))).to eq("top")
        ensure
          browser&.quit
        end
      end

      it "errors when extension is unavailable" do
        begin
          browser = Browser.new(extensions: [File.expand_path("../support/non_existent.js", __dir__)])
          expect { browser.go_to }.to raise_error(Errno::ENOENT)
        ensure
          browser&.quit
        end
      end

      it "supports evaluation of JavaScript before page loads" do
        begin
          browser = Browser.new(base_url: base_url)

          browser.evaluate_on_new_document <<~JS
            Object.defineProperty(navigator, "languages", {
              get: function() { return ["tlh"]; }
            });
          JS

          browser.go_to("/ferrum/with_user_js")
          language = browser.at_xpath("//*[@id='browser-languages']/text()").text
          expect(language).to eq("tlh")
        ensure
          browser&.quit
        end
      end
    end

    context "javascript errors" do
      let(:browser) { Browser.new(base_url: base_url, js_errors: true) }

      it "propagates a Javascript error to a ruby exception" do
        expect {
          browser.execute(%(throw new Error("zomg")))
        }.to raise_error(Ferrum::JavaScriptError) { |e|
          expect(e.message).to include("Error: zomg")
        }
      end

      it "propagates an asynchronous Javascript error on the page to a ruby exception" do
        expect {
          browser.execute "setTimeout(function() { omg }, 0)"
          sleep 0.01
          browser.execute ""
        }.to raise_error(Ferrum::JavaScriptError, /ReferenceError.*omg/)
      end

      it "propagates a synchronous Javascript error on the page to a ruby exception" do
        expect {
          browser.execute "omg"
        }.to raise_error(Ferrum::JavaScriptError, /ReferenceError.*omg/)
      end

      it "does not re-raise a Javascript error if it is rescued" do
        expect {
          browser.execute "setTimeout(function() { omg }, 0)"
          sleep 0.01
          browser.execute ""
        }.to raise_error(Ferrum::JavaScriptError, /ReferenceError.*omg/)

        # should not raise again
        expect(browser.evaluate("1+1")).to eq(2)
      end

      it "propagates a Javascript error during page load to a ruby exception" do
        expect { browser.go_to("/ferrum/js_error") }.to raise_error(Ferrum::JavaScriptError)
      end

      it "does not propagate a Javascript error to ruby if error raising disabled" do
        begin
          browser = Browser.new(base_url: base_url, js_errors: false)
          browser.go_to("/ferrum/js_error")
          browser.execute "setTimeout(function() { omg }, 0)"
          sleep 0.1
          expect(browser.body).to include("hello")
        ensure
          browser&.quit
        end
      end

      it "does not propagate a Javascript error to ruby if error raising disabled and client restarted" do
        begin
          browser = Browser.new(base_url: base_url, js_errors: false)
          browser.restart
          browser.go_to("/ferrum/js_error")
          browser.execute "setTimeout(function() { omg }, 0)"
          sleep 0.1
          expect(browser.body).to include("hello")
        ensure
          browser&.quit
        end
      end
    end

    context "browser failed responses" do
      let(:port) { server.port }

      it "do not occur when DNS correct" do
        expect { browser.go_to("http://localhost:#{port}/") }.not_to raise_error
      end

      it "handles when DNS incorrect" do
        expect { browser.go_to("http://nope:#{port}/") }.to raise_error(
          Ferrum::StatusError,
          %r{Request to http://nope:\d+/ failed to reach server, check DNS and server status}
        )
      end

      it "has a descriptive message when DNS incorrect" do
        url = "http://nope:#{port}/"
        expect {
          browser.go_to(url)
        }.to raise_error(
          Ferrum::StatusError,
          %r{Request to http://nope:#{port}/ failed to reach server, check DNS and server status}
        )
      end

      it "reports open resource requests" do
        begin
          old_timeout = browser.timeout
          browser.timeout = 2
          expect {
            browser.go_to("/ferrum/visit_timeout")
          }.to raise_error(
            Ferrum::PendingConnectionsError,
            %r{Request to http://.*/ferrum/visit_timeout reached server, but there are still pending connections: http://.*/ferrum/really_slow}
          )
        ensure
          browser.timeout = old_timeout
        end
      end

      it "reports open resource requests for main frame" do
        begin
          prev_timeout = browser.timeout
          browser.timeout = 0.1

          expect {
            browser.go_to("/ferrum/really_slow")
          }.to raise_error(
            Ferrum::PendingConnectionsError,
            %r{Request to http://.*/ferrum/really_slow reached server, but there are still pending connections: http://.*/ferrum/really_slow}
          )
        ensure
          browser.timeout = prev_timeout
        end
      end

      it "does not report open resources when there are none" do
        begin
          old_timeout = browser.timeout
          browser.timeout = 4
          expect { browser.go_to("/ferrum/really_slow") }.not_to raise_error
        ensure
          browser.timeout = old_timeout
        end
      end

      it "does not report open resources when pending_connection_errors is set to false" do
        begin
          browser = Browser.new(base_url: base_url, pending_connection_errors: false, timeout: 0.1)

          expect { browser.go_to("/ferrum/really_slow") }.not_to raise_error
        ensure
          browser&.quit
        end
      end
    end

    it "allows the driver to have a fixed port" do
      begin
        browser = Browser.new(port: 12345)
        browser.go_to(base_url)

        expect { TCPServer.new("127.0.0.1", 12345) }.to raise_error(Errno::EADDRINUSE)
      ensure
        browser&.quit
      end
    end

    it "allows the driver to run tests on external process" do
      with_external_browser do |url|
        begin
          browser = Browser.new(url: url)
          browser.go_to(base_url)
          expect(browser.body).to include("Hello world!")
        ensure
          browser&.quit
        end
      end
    end

    it "allows the driver to have a custom host", skip: ENV["BROWSER_TEST_HOST"].nil? do
      begin
        # Use custom host "pointing" to localhost in /etc/hosts or iptables for this.
        # https://superuser.com/questions/516208/how-to-change-ip-address-to-point-to-localhost
        browser = Browser.new(host: ENV["BROWSER_TEST_HOST"], port: 12345)
        browser.go_to(base_url)

        expect {
          TCPServer.new(ENV["BROWSER_TEST_HOST"], 12345)
        }.to raise_error(Errno::EADDRINUSE)
      ensure
        browser&.quit
      end
    end

    it "lists the open windows" do
      browser.go_to

      browser.execute <<~JS
        window.open("/ferrum/simple", "popup")
      JS

      sleep 0.1

      expect(browser.targets.size).to eq(2)

      browser.execute <<~JS
        window.open("/ferrum/simple", "popup2")
      JS

      sleep 0.1

      expect(browser.targets.size).to eq(3)

      popup2, _ = browser.windows(:last)
      expect(popup2.body).to include("Test")
      # Browser isn't dead, current page after executing JS closes connection
      # and we don't have a chance to push response to the Queue. Since the
      # queue and websocket are closed and response is nil the proper guess
      # would be that browser is dead, but in fact the page is dead and
      # browser is fully alive.
      popup2.execute("window.close()") rescue Ferrum::DeadBrowserError

      sleep 0.1

      expect(browser.targets.size).to eq(2)
    end

    context "a new window inherits settings" do
      it "inherits size" do
        browser.go_to
        browser.resize(width: 1200, height: 800)
        page = browser.create_page
        expect(page.viewport_size).to eq [1200, 800]
      end
    end

    it "resizes windows" do
      browser.go_to

      expect(browser.targets.size).to eq(1)

      browser.execute <<-JS
        window.open("/ferrum/simple", "popup1")
      JS

      sleep 0.1

      browser.execute <<-JS
        window.open("/ferrum/simple", "popup2")
      JS

      popup1, popup2 = browser.windows(:last, 2)
      popup1.resize(width: 100, height: 200)
      popup2.resize(width: 200, height: 100)

      expect(popup1.viewport_size).to eq([100, 200])
      expect(popup2.viewport_size).to eq([200, 100])
    end

    it "clears local storage after reset" do
      browser.go_to
      browser.execute <<~JS
        localStorage.setItem("key", "value");
      JS
      value = browser.evaluate <<~JS
        localStorage.getItem("key");
      JS

      expect(value).to eq("value")

      browser.reset

      browser.go_to
      value = browser.evaluate <<~JS
        localStorage.getItem("key");
      JS
      expect(value).to be_nil
    end

    it "synchronizes page loads properly" do
      browser.go_to("/ferrum/index")
      browser.at_xpath("//a[text() = 'JS redirect']").click
      sleep 0.1
      expect(browser.body).to include("Hello world")
    end

    it "does not run into content quads error" do
      browser.go_to("/ferrum/index")

      allow_any_instance_of(Node).to receive(:get_content_quads).and_raise(Ferrum::BrowserError, "message" => "Could not compute content quads")

      browser.at_xpath("//a[text() = 'JS redirect']").click
      expect(browser.body).to include("Hello world")
    end

    it "returns BR as new line in #text" do
      browser.go_to("/ferrum/simple")
      el = browser.at_css("#break")
      expect(el.inner_text).to eq("Foo\nBar")
      expect(browser.at_css("#break").text).to eq("FooBar")
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

    context "current_url" do
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
    end

    context "window switching support" do
      it "waits for the window to load" do
        browser.go_to

        browser.execute <<-JS
          window.open("/ferrum/slow", "popup")
        JS

        popup, _ = browser.windows(:last)
        expect(popup.body).to include("slow page")
        popup.close
      end

      it "can access a second window of the same name" do
        browser.go_to

        browser.execute <<-JS
          window.open("/ferrum/simple", "popup")
        JS

        popup, _ = browser.windows(:last)
        expect(popup.body).to include("Test")
        popup.close

        sleep 0.5 # https://github.com/ChromeDevTools/devtools-protocol/issues/145

        browser.execute <<-JS
          window.open("/ferrum/simple", "popup")
        JS

        sleep 0.5 # https://github.com/ChromeDevTools/devtools-protocol/issues/145

        same, _ = browser.windows(:last)
        expect(same.body).to include("Test")
        same.close
      end
    end

    it "handles obsolete node during an attach_file", skip: true do
      browser.go_to("/ferrum/attach_file")
      browser.attach_file "file", __FILE__
    end

    context "whitespace stripping tests", skip: true do
      before do
        browser.go_to("/ferrum/filter_text_test")
      end

      it "gets text" do
        expect(browser.at_css("#foo").text).to eq "foo"
      end

      it "gets text stripped whitespace" do
        expect(browser.at_css("#bar").inner_text).to eq "bar"
      end

      it "gets text stripped whitespace and then converts nbsp to space" do
        expect(browser.at_css("#baz").inner_text).to eq " baz    "
      end

      it "gets text stripped whitespace" do
        expect(browser.at_css("#qux").text).to eq "  \u3000 qux \u3000  "
      end
    end

    context "supports accessing element properties" do
      before do
        browser.go_to("/ferrum/attributes_properties")
      end

      it "gets property innerHTML" do
        expect(browser.at_css(".some_other_class").property("innerHTML")).to eq "<p>foobar</p>"
      end

      it "gets property outerHTML" do
        el = browser.at_css(".some_other_class")
        expect(el.property("outerHTML"))
          .to eq %(<div class="some_other_class"><p>foobar</p></div>)
      end

      it "gets non existent property" do
        el = browser.at_css(".some_other_class")
        expect(el.property("does_not_exist")).to eq nil
      end
    end

    context "SVG tests" do
      before do
        browser.go_to("/ferrum/svg_test")
      end

      it "gets text from tspan node" do
        expect(browser.at_css("tspan").text).to eq "svg foo"
      end
    end

    it "can go back when history state has been pushed" do
      browser.go_to
      browser.execute(%(window.history.pushState({foo: "bar"}, "title", "bar2.html");))
      expect(browser.current_url).to eq(base_url("/bar2.html"))
      expect { browser.back }.not_to raise_error
      expect(browser.current_url).to eq(base_url("/"))
    end

    it "can go forward when history state is used" do
      browser.go_to
      browser.execute(%(window.history.pushState({foo: "bar"}, "title", "bar2.html");))
      expect(browser.current_url).to eq(base_url("/bar2.html"))
      # don't use #back here to isolate the test
      browser.execute("window.history.go(-1);")
      expect(browser.current_url).to eq(base_url("/"))
      expect { browser.forward }.not_to raise_error
      expect(browser.current_url).to eq(base_url("/bar2.html"))
    end

    it "waits for page to be reloaded" do
      browser.go_to("/ferrum/auto_refresh")
      expect(browser.body).to include("Visited 0 times")

      browser.wait_for_reload(5)

      expect(browser.body).to include("Visited 1 times")
    end

    it "can bypass csp headers" do
      browser.go_to("/csp")
      browser.add_script_tag(content: "window.__injected = 42")
      expect(browser.evaluate("window.__injected")).to be_nil

      browser.bypass_csp
      browser.reload
      browser.add_script_tag(content: "window.__injected = 42")

      expect(browser.evaluate("window.__injected")).to eq(42)
    end

    if Ferrum.mri? && !Ferrum.windows?
      require "pty"
      require "timeout"

      context "with pty" do
        before do
          Tempfile.open(%w[test rb]) do |file|
            file.print(script)
            file.flush

            Timeout.timeout(10) do
              PTY.spawn("bundle exec ruby #{file.path}") do |read, write, pid|
                sleep 0.01 until read.readline.chomp == "Please type enter"
                write.puts
                sleep 0.1 until (status = PTY.check(pid))
                @status = status
              end
            end
          end
        end

        let(:script) do
          <<-RUBY
            require "ferrum"
            browser = Ferrum::Browser.new
            browser.go_to("http://example.com")
            puts "Please type enter"
            sleep 1
            browser.current_url
          RUBY
        end

        it do
          expect(@status).to be_success
        end
      end
    end
  end
end
