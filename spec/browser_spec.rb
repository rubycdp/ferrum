# frozen_string_literal: true

require "spec_helper"

module Ferrum
  describe Browser do
    let!(:browser) { Browser.new(base_url: @server.base_url) }

    after { browser.reset }

    it "supports a custom path" do
      begin
        original_path = PROJECT_ROOT + "/spec/support/chrome_path"
        File.write(original_path, browser.process.path)

        file = PROJECT_ROOT + "/spec/support/custom_chrome_called"
        path = PROJECT_ROOT + "/spec/support/custom_chrome"

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
          browser.goto(base_url("/ferrum/console_log"))
          expect(logger.string).to include("Hello world")
        ensure
          browser&.quit
        end
      end
    end

    it "raises an error and restarts the client if the client dies while executing a command" do
      expect { browser.crash }.to raise_error(Ferrum::DeadBrowserError)
      browser.goto
      expect(browser.body).to include("Hello world")
    end

    it "stops silently before goto call" do
      browser = Browser.new
      expect { browser.quit }.not_to raise_error
    end

    it "has a viewport size of 1024x768 by default" do
      browser.goto

      expect(
        browser.evaluate("[window.innerWidth, window.innerHeight]")
      ).to eq([1024, 768])
    end

    it "allows the viewport to be resized" do
      browser.goto
      browser.resize(width: 200, height: 400)
      expect(
        browser.evaluate("[window.innerWidth, window.innerHeight]")
      ).to eq([200, 400])
    end

    # it "defaults viewport maximization to 1366x768" do
    #   browser.goto
    #   browser.current_window.maximize
    #   expect(browser.current_window.size).to eq([1366, 768])
    # end

    # it "allows custom maximization size" do
    #   begin
    #     browser.options[:screen_size] = [1600, 1200]
    #     browser.goto
    #     browser.current_window.maximize
    #     expect(browser.current_window.size).to eq([1600, 1200])
    #   ensure
    #     browser.options.delete(:screen_size)
    #   end
    # end

    it "allows the page to be scrolled" do
      browser.goto("/ferrum/long_page")
      browser.resize(width: 10, height: 10)
      browser.scroll_to(200, 100)
      expect(
        browser.evaluate("[window.scrollX, window.scrollY]")
      ).to eq([200, 100])
    end

    it "supports specifying viewport size with an option" do
      begin
        browser = Browser.new(window_size: [800, 600])
        browser.goto(base_url)
        expect(
          browser.evaluate("[window.innerWidth, window.innerHeight]")
        ).to eq([800, 600])
      ensure
        browser&.quit
      end
    end

    it "supports clicking precise coordinates" do
      browser.goto("/ferrum/click_coordinates")
      browser.click_coordinates(100, 150)
      expect(browser.body).to include("x: 100, y: 150")
    end

    it "supports executing multiple lines of javascript" do
      browser.execute <<-JS
        var a = 1
        var b = 2
        window.result = a + b
      JS
      expect(browser.evaluate("window.result")).to eq(3)
    end

    it "operates a timeout when communicating with browser" do
      begin
        prev_timeout = browser.timeout
        browser.timeout = 0.1
        expect { browser.goto("/ferrum/really_slow") }.to raise_error(TimeoutError)
      ensure
        browser.timeout = prev_timeout
      end
    end

    it "supports stopping the session", skip: Ferrum.windows? do
      browser = Browser.new
      pid = browser.process.pid

      expect(Process.kill(0, pid)).to eq(1)
      browser.quit

      expect { Process.kill(0, pid) }.to raise_error(Errno::ESRCH)
    end

    context "extending browser javascript" do
      it "supports extending the browser's world" do
        begin
          browser = Browser.new(base_url: @server.base_url,
                                extensions: [File.expand_path("support/geolocation.js", __dir__)])

          browser.goto("/ferrum/requiring_custom_extension")

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

      it "errors when extension is unavailable" do
        begin
          browser = Browser.new(extensions: [File.expand_path("../support/non_existent.js", __dir__)])
          expect { browser.goto }.to raise_error(Errno::ENOENT)
        ensure
          browser&.quit
        end
      end
    end

    context "javascript errors" do
      let(:browser) { Browser.new(base_url: @server.base_url, js_errors: true) }

      it "propagates a Javascript error to a ruby exception" do
        expect do
          browser.execute(%(throw new Error("zomg")))
        end.to raise_error(Ferrum::JavaScriptError) { |e|
          expect(e.message).to include("Error: zomg")
        }
      end

      it "propagates an asynchronous Javascript error on the page to a ruby exception" do
        expect do
          browser.execute "setTimeout(function() { omg }, 0)"
          sleep 0.01
          browser.execute ""
        end.to raise_error(Ferrum::JavaScriptError, /ReferenceError.*omg/)
      end

      it "propagates a synchronous Javascript error on the page to a ruby exception" do
        expect do
          browser.execute "omg"
        end.to raise_error(Ferrum::JavaScriptError, /ReferenceError.*omg/)
      end

      it "does not re-raise a Javascript error if it is rescued" do
        expect do
          browser.execute "setTimeout(function() { omg }, 0)"
          sleep 0.01
          browser.execute ""
        end.to raise_error(Ferrum::JavaScriptError)

        # should not raise again
        expect(browser.evaluate("1+1")).to eq(2)
      end

      it "propagates a Javascript error during page load to a ruby exception" do
        expect { browser.goto("/ferrum/js_error") }.to raise_error(Ferrum::JavaScriptError)
      end

      it "does not propagate a Javascript error to ruby if error raising disabled" do
        begin
          browser = Browser.new(base_url: @server.base_url, js_errors: false)
          browser.goto("/ferrum/js_error")
          browser.execute "setTimeout(function() { omg }, 0)"
          sleep 0.1
          expect(browser.body).to include("hello")
        ensure
          browser&.quit
        end
      end

      it "does not propagate a Javascript error to ruby if error raising disabled and client restarted" do
        begin
          browser = Browser.new(base_url: @server.base_url, js_errors: false)
          browser.restart
          browser.goto("/ferrum/js_error")
          browser.execute "setTimeout(function() { omg }, 0)"
          sleep 0.1
          expect(browser.body).to include("hello")
        ensure
          browser&.quit
        end
      end
    end

    context "browser failed responses" do
      let(:port) { @server.port }

      it "do not occur when DNS correct" do
        expect { browser.goto("http://localhost:#{port}/") }.not_to raise_error
      end

      it "handles when DNS incorrect" do
        expect { browser.goto("http://nope:#{port}/") }.to raise_error(Ferrum::StatusError)
      end

      it "has a descriptive message when DNS incorrect" do
        url = "http://nope:#{port}/"
        expect { browser.goto(url) }
          .to raise_error(
            Ferrum::StatusError,
            %(Request to #{url} failed to reach server, check DNS and/or server status)
          )
      end

      it "reports open resource requests", skip: true do
        old_timeout = browser.timeout
        begin
          browser.timeout = 2
          expect do
            browser.goto("/ferrum/visit_timeout")
          end.to raise_error(Ferrum::StatusError, %r{resources still waiting http://.*/ferrum/really_slow})
        ensure
          browser.timeout = old_timeout
        end
      end

      it "does not report open resources where there are none", skip: true do
        old_timeout = browser.timeout
        begin
          browser.timeout = 2
          expect do
            browser.goto("/ferrum/really_slow")
          end.to raise_error(Ferrum::StatusError) { |error|
            expect(error.message).not_to include("resources still waiting")
          }
        ensure
          browser.timeout = old_timeout
        end
      end
    end

    it "can clear memory cache" do
      browser.clear_memory_cache

      browser.goto("/ferrum/cacheable")
      first_request = browser.network_traffic.last
      expect(browser.network_traffic.length).to eq(1)
      expect(first_request.response.status).to eq(200)

      browser.refresh
      expect(browser.network_traffic.length).to eq(2)
      expect(browser.network_traffic.last.response.status).to eq(304)

      browser.clear_memory_cache

      browser.refresh
      another_request = browser.network_traffic.last
      expect(browser.network_traffic.length).to eq(3)
      expect(another_request.response.status).to eq(200)
    end

    context "status code support" do
      it "determines status from the simple response" do
        browser.goto("/ferrum/status/500")
        expect(browser.status).to eq(500)
      end

      it "determines status code when the page has a few resources" do
        browser.goto("/ferrum/with_different_resources")
        expect(browser.status).to eq(200)
      end

      it "determines status code even after redirect" do
        browser.goto("/ferrum/redirect")
        expect(browser.status).to eq(200)
      end
    end

    it "allows the driver to have a fixed port" do
      begin
        browser = Browser.new(port: 12345)
        browser.goto(base_url)

        expect { TCPServer.new("127.0.0.1", 12345) }.to raise_error(Errno::EADDRINUSE)
      ensure
        browser&.quit
      end
    end

    it "allows the driver to run tests on external process" do
      with_external_browser do |url|
        begin
          browser = Browser.new(url: url)
          browser.goto(base_url)
          expect(browser.body).to include("Hello world!")
        ensure
          browser&.quit
        end
      end
    end

    it "allows the driver to have a custom host" do
      begin
        # Use custom host "pointing" to localhost, specified by BROWSER_TEST_HOST env var.
        # Use /etc/hosts or iptables for this: https://superuser.com/questions/516208/how-to-change-ip-address-to-point-to-localhost
        host = ENV["BROWSER_TEST_HOST"]

        skip "BROWSER_TEST_HOST not set" if host.nil? # skip test if var is unspecified

        browser = Browser.new(host: host, port: 12345)
        browser.goto(base_url)

        expect { TCPServer.new(host, 12345) }.to raise_error(Errno::EADDRINUSE)
      ensure
        browser&.quit
      end
    end

    # it "lists the open windows" do
    #   browser.goto
    #
    #   browser.execute <<-JS
    #     window.open("/ferrum/simple", "popup")
    #   JS
    #
    #   expect(browser.window_handles.size).to eq(2)
    #
    #   popup2 = browser.window_opened_by do
    #     browser.execute <<-JS
    #       window.open("/ferrum/simple", "popup2")
    #     JS
    #   end
    #
    #   expect(browser.window_handles.size).to eq(3)
    #
    #   browser.within_window(popup2) do
    #     expect(browser.body).to include("Test")
    #     browser.execute("window.close()")
    #   end
    #
    #   sleep 0.1
    #
    #   expect(browser.window_handles.size).to eq(2)
    # end
    #
    # context "a new window inherits settings" do
    #   it "inherits size" do
    #     browser.goto
    #     browser.current_window.resize_to(1200, 800)
    #     new_tab = browser.open_new_window
    #     expect(new_tab.size).to eq [1200, 800]
    #   end
    #
    #   it "inherits url_blacklist" do
    #     @driver.browser.url_blacklist = ["unwanted"]
    #     @session.goto
    #     new_tab = @session.open_new_window
    #     @session.within_window(new_tab) do
    #       @session.goto "/ferrum/url_blacklist"
    #       expect(@session).to have_content("We are loading some unwanted action here")
    #       @session.within_frame "framename" do
    #         expect(@session.html).not_to include("We shouldn't see this.")
    #       end
    #     end
    #   end
    #
    #   it "inherits url_whitelist" do
    #     @session.goto
    #     @driver.browser.url_whitelist = ["url_whitelist", "/ferrum/wanted"]
    #     new_tab = @session.open_new_window
    #     @session.within_window(new_tab) do
    #       @session.goto "/ferrum/url_whitelist"
    #
    #       expect(@session).to have_content("We are loading some wanted action here")
    #       @session.within_frame "framename" do
    #         expect(@session).to have_content("We should see this.")
    #       end
    #       @session.within_frame "unwantedframe" do
    #         # make sure non whitelisted urls are blocked
    #         expect(@session).not_to have_content("We shouldn't see this.")
    #       end
    #     end
    #   end
    # end
    #
    # it "resizes windows" do
    #   @session.goto
    #
    #   popup1 = @session.window_opened_by do
    #     @session.execute_script <<-JS
    #       window.open("/ferrum/simple", "popup1")
    #     JS
    #   end
    #
    #   popup2 = @session.window_opened_by do
    #     @session.execute_script <<-JS
    #       window.open("/ferrum/simple", "popup2")
    #     JS
    #   end
    #
    #   popup1.resize_to(100, 200)
    #   popup2.resize_to(200, 100)
    #
    #   expect(popup1.size).to eq([100, 200])
    #   expect(popup2.size).to eq([200, 100])
    # end

    it "clears local storage after reset" do
      browser.goto
      browser.execute <<~JS
        localStorage.setItem("key", "value");
      JS
      value = browser.evaluate <<~JS
        localStorage.getItem("key");
      JS

      expect(value).to eq("value")

      browser.reset

      browser.goto
      value = browser.evaluate <<~JS
        localStorage.getItem("key");
      JS
      expect(value).to be_nil
    end

    context "evaluate" do
      it "can return an element" do
        browser.goto("/ferrum/type")
        element = browser.evaluate(%(document.getElementById("empty_input")))
        expect(element).to eq(browser.at_css("#empty_input"))
      end

      it "can return structures with elements" do
        browser.goto("/ferrum/type")
        result = browser.evaluate <<~JS
          {
            a: document.getElementById("empty_input"),
            b: { c: document.querySelectorAll("#empty_textarea, #filled_textarea") }
          }
        JS

        expect(result).to eq(
          "a" => browser.at_css("#empty_input"),
          "b" => {
            "c" => browser.css("#empty_textarea, #filled_textarea")
          }
        )
      end
    end

    context "evaluate_async" do
      it "handles evaluate_async value properly" do
        expect(browser.evaluate_async("arguments[0](null)", 5)).to be_nil
        expect(browser.evaluate_async("arguments[0](false)", 5)).to be false
        expect(browser.evaluate_async("arguments[0](true)", 5)).to be true
        expect(browser.evaluate_async(%(arguments[0]({foo: "bar"})), 5)).to eq("foo" => "bar")
      end

      it "will timeout" do
        expect do
          browser.evaluate_async("var callback=arguments[0]; setTimeout(function(){callback(true)}, 4000)", 1)
        end.to raise_error Ferrum::ScriptTimeoutError
      end
    end

    # it "can get the frames url" do
    #   browser.goto("/ferrum/frames")
    #
    #   browser.within_frame(0) do
    #     expect(browser.frame_url).to end_with("/ferrum/slow")
    #     expect(browser.current_url).to end_with("/ferrum/frames")
    #   end
    #
    #   expect(browser.frame_url).to end_with("/ferrum/frames")
    #   expect(browser.current_url).to end_with("/ferrum/frames")
    # end
  end
end
