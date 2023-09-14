# frozen_string_literal: true

describe Ferrum::Browser do
  describe "#new" do
    let(:logger) { StringIO.new }

    context ":browser_path argument" do
      it "includes the process output in the error" do
        path = "#{PROJECT_ROOT}/spec/support/broken_chrome"

        expect do
          Ferrum::Browser.new(browser_path: path)
        end.to raise_error(Ferrum::ProcessTimeoutError) do |e|
          expect(e.output).to include "Broken Chrome error message"
        end
      end

      it "supports custom chrome path" do
        original_path = "#{PROJECT_ROOT}/spec/support/chrome_path"
        File.write(original_path, browser.process.path)

        file = "#{PROJECT_ROOT}/spec/support/custom_chrome_called"
        path = "#{PROJECT_ROOT}/spec/support/custom_chrome"

        browser = Ferrum::Browser.new(browser_path: path)

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

    it "supports :logger argument" do
      browser = Ferrum::Browser.new(logger: logger)
      browser.go_to(base_url("/ferrum/console_log"))
      expect(logger.string).to include("Hello world")
    ensure
      browser&.quit
    end

    it "supports :ignore_default_browser_options argument" do
      defaults = Ferrum::Browser::Options::Chrome.options.except("disable-web-security")
      browser = Ferrum::Browser.new(ignore_default_browser_options: true, browser_options: defaults)
      browser.go_to(base_url("/ferrum/console_log"))
    ensure
      browser&.quit
    end

    it "supports :process_timeout argument" do
      path = "#{PROJECT_ROOT}/spec/support/no_chrome"

      expect do
        Ferrum::Browser.new(browser_path: path, process_timeout: 2)
      end.to raise_error(
        Ferrum::ProcessTimeoutError,
        "Browser did not produce websocket url within 2 seconds, try to increase `:process_timeout`. See https://github.com/rubycdp/ferrum#customization"
      )
    end

    context ":extensions argument" do
      it "extends the browser's world with files" do
        browser = Ferrum::Browser.new(base_url: base_url,
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

      it "extends the browser's world with source" do
        browser = Ferrum::Browser.new(base_url: base_url,
                                      extensions: [{ source: "window.secret = 'top'" }])

        browser.go_to("/ferrum/requiring_custom_extension")

        expect(browser.evaluate(%(window.secret))).to eq("top")
      ensure
        browser&.quit
      end

      it "errors when extension is unavailable" do
        browser = Ferrum::Browser.new(extensions: [File.expand_path("../support/non_existent.js", __dir__)])
        expect { browser.go_to }.to raise_error(Errno::ENOENT)
      ensure
        browser&.quit
      end
    end

    it "supports :port argument" do
      browser = Ferrum::Browser.new(port: 12_345)
      browser.go_to(base_url)

      expect { TCPServer.new("127.0.0.1", 12_345) }.to raise_error(Errno::EADDRINUSE)
    ensure
      browser&.quit
    end

    it "supports :url argument" do
      with_external_browser do |url|
        browser = Ferrum::Browser.new(url: url)
        browser.go_to(base_url)
        expect(browser.body).to include("Hello world!")
      ensure
        browser&.quit
      end
    end

    it "supports :host argument", skip: ENV["BROWSER_TEST_HOST"].nil? do
      # Use custom host "pointing" to localhost in /etc/hosts or iptables for this.
      # https://superuser.com/questions/516208/how-to-change-ip-address-to-point-to-localhost
      browser = Ferrum::Browser.new(host: ENV.fetch("BROWSER_TEST_HOST"), port: 12_345)
      browser.go_to(base_url)

      expect do
        TCPServer.new(ENV.fetch("BROWSER_TEST_HOST"), 12_345)
      end.to raise_error(Errno::EADDRINUSE)
    ensure
      browser&.quit
    end

    context ":proxy argument" do
      let(:options) { {} }
      let(:proxy) { Ferrum::Proxy.start(**options) }

      after { proxy.stop }

      context "without authorization" do
        it "works without authorization" do
          browser = Ferrum::Browser.new(
            proxy: { host: proxy.host, port: proxy.port }
          )

          browser.go_to("https://example.com")
          expect(browser.network.status).to eq(200)
          expect(browser.body).to include("Example Domain")
        ensure
          browser&.quit
        end
      end

      context "with authorization" do
        let(:options) { Hash(user: "user", password: "pa$$") }

        it "works with right password" do
          browser = Ferrum::Browser.new(
            proxy: { host: proxy.host, port: proxy.port, **options }
          )

          browser.go_to("https://example.com")
          expect(browser.network.status).to eq(200)
          expect(browser.body).to include("Example Domain")
        ensure
          browser&.quit
        end

        it "breaks with wrong password" do
          browser = Ferrum::Browser.new(
            proxy: { host: proxy.host, port: proxy.port, user: "u1", password: "p1" }
          )

          if browser.headless_new?
            expect { browser.go_to("https://example.com") }.to raise_error(
              Ferrum::StatusError,
              "Request to https://example.com failed (net::ERR_HTTP_RESPONSE_CODE_FAILURE)"
            )
          else
            browser.go_to("https://example.com")
          end

          expect(browser.network.status).to eq(407)
        ensure
          browser&.quit
        end
      end

      context "with rotation", skip: "Think how to make it working on CI" do
        it "works after disposing context" do
          browser = Ferrum::Browser.new(
            proxy: { host: proxy.host, port: proxy.port, **options }
          )

          proxy.rotate(host: "host", port: 0, user: "user", password: "password")
          browser.create_page(new_context: true) do |page|
            page.go_to("https://api.ipify.org?format=json")
            expect(page.network.status).to eq(200)
            expect(page.body).to include("x.x.x.x")
          end

          proxy.rotate(host: "host", port: 0, user: "user", password: "password")
          browser.create_page(new_context: true) do |page|
            page.go_to("https://api.ipify.org?format=json")
            expect(page.network.status).to eq(200)
            expect(page.body).to include("x.x.x.x")
          end
        ensure
          browser&.quit
        end
      end
    end

    it "supports :pending_connection_errors argument" do
      browser = Ferrum::Browser.new(base_url: base_url, pending_connection_errors: false, timeout: 0.5)

      expect { browser.go_to("/ferrum/really_slow") }.not_to raise_error
    ensure
      browser&.quit
    end

    context ":save_path argument" do
      let(:filename) { "attachment.pdf" }
      let(:browser) do
        Ferrum::Browser.new(
          base_url: Ferrum::Server.server.base_url,
          save_path: save_path
        )
      end

      context "with absolute path" do
        let(:save_path) { "/tmp/ferrum" }

        it "saves an attachment" do
          # Also https://github.com/puppeteer/puppeteer/issues/10161
          skip "https://bugs.chromium.org/p/chromium/issues/detail?id=1444729" if browser.headless_new?

          browser.go_to("/#{filename}")

          expect(File.exist?("#{save_path}/#{filename}")).to be true
        ensure
          FileUtils.rm_rf(save_path)
        end
      end

      context "with local path" do
        let(:save_path) { "spec/tmp" }

        it "raises an error" do
          expect do
            browser.go_to("/#{filename}")
          end.to raise_error(Ferrum::Error, "supply absolute path for `:save_path` option")
        end
      end
    end
  end

  describe "#crash" do
    it "raises an error" do
      expect { browser.crash }.to raise_error(Ferrum::DeadBrowserError)
    end

    it "restarts the client" do
      expect { browser.crash }.to raise_error(Ferrum::DeadBrowserError)

      browser.go_to

      expect(browser.body).to include("Hello world")
    end
  end

  describe "#version" do
    it "returns browser version information" do
      version_info = browser.version

      expect(version_info).to be_kind_of(Ferrum::Browser::VersionInfo)
      expect(version_info.protocol_version).to_not be(nil)
      expect(version_info.protocol_version).to_not be_empty
      expect(version_info.product).to_not be(nil)
      expect(version_info.product).to_not be_empty
      expect(version_info.revision).to_not be(nil)
      expect(version_info.revision).to_not be_empty
      expect(version_info.user_agent).to_not be(nil)
      expect(version_info.user_agent).to_not be_empty
      expect(version_info.js_version).to_not be(nil)
      expect(version_info.js_version).to_not be_empty
    end
  end

  describe "#quit" do
    it "stops silently before go_to call" do
      browser = Ferrum::Browser.new
      expect { browser.quit }.not_to raise_error
    end

    it "supports stopping the session", skip: Ferrum::Utils::Platform.windows? do
      browser = Ferrum::Browser.new
      pid = browser.process.pid

      expect(Process.kill(0, pid)).to eq(1)
      browser.quit

      expect { Process.kill(0, pid) }.to raise_error(Errno::ESRCH)
    end
  end

  describe "#resize" do
    it "allows the viewport to be resized" do
      browser.go_to
      browser.resize(width: 200, height: 400)
      expect(browser.viewport_size).to eq([200, 400])
    end

    it "inherits size for a new window" do
      browser.go_to
      browser.resize(width: 1200, height: 800)
      page = browser.create_page
      expect(page.viewport_size).to eq [1200, 800]
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
      popup1&.resize(width: 100, height: 200)
      popup2&.resize(width: 200, height: 100)

      expect(popup1&.viewport_size).to eq([100, 200])
      expect(popup2&.viewport_size).to eq([200, 100])
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

      it "resizes to normal from fullscreen window state" do
        browser.go_to(path)
        browser.resize(fullscreen: true)
        browser.resize(width: 200, height: 400)
        expect(browser.viewport_size).to eq([200, 400])
      end
    end
  end

  describe "#evaluate_on_new_document" do
    it "supports evaluation of JavaScript before page loads" do
      browser = Ferrum::Browser.new(base_url: base_url)

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

  describe "#targets" do
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

      popup2, = browser.windows(:last)
      expect(popup2.body).to include("Test")
      # Browser isn't dead, current page after executing JS closes connection
      # and we don't have a chance to push response to the Queue. Since the
      # queue and websocket are closed and response is nil the proper guess
      # would be that browser is dead, but in fact the page is dead and
      # browser is fully alive.
      begin
        popup2.execute("window.close()")
      rescue StandardError
        Ferrum::DeadBrowserError
      end

      sleep 0.1

      expect(browser.targets.size).to eq(2)
    end
  end

  describe "#reset" do
    it "clears local storage" do
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
  end

  describe "#create_page" do
    it "supports calling without block" do
      expect(browser.contexts.size).to eq(0)
      expect(browser.targets.size).to eq(0)

      page = browser.create_page
      page.go_to("/ferrum/simple")

      expect(browser.contexts.size).to eq(1)
      expect(browser.targets.size).to eq(1)
    end

    it "supports calling with block" do
      expect(browser.contexts.size).to eq(0)
      expect(browser.targets.size).to eq(0)

      browser.create_page do |page|
        page.go_to("/ferrum/simple")
      end

      sleep 1 # It may take longer to close the target
      expect(browser.contexts.size).to eq(1)
      expect(browser.targets.size).to eq(0)
    end

    context "with :new_context" do
      it "supports calling without block" do
        expect(browser.contexts.size).to eq(0)

        page = browser.create_page(new_context: true)
        page.go_to("/ferrum/simple")

        expect(browser.contexts.size).to eq(1)
        expect(page.context.targets.size).to eq(1)

        page.context.create_page
        expect(page.context.targets.size).to eq(2)
        page.context.dispose
        expect(browser.contexts.size).to eq(0)
      end

      it "supports calling with block" do
        expect(browser.contexts.size).to eq(0)

        browser.create_page(new_context: true) do |page|
          page.go_to("/ferrum/simple")
        end

        expect(browser.contexts.size).to eq(0)
      end
    end

    context "with :proxy" do
      let(:options) { {} }
      let(:proxy) { Ferrum::Proxy.start(**options) }

      after { proxy.stop }

      context "without authorization" do
        it "succeeds" do
          expect(browser.contexts.size).to eq(0)

          page = browser.create_page(proxy: { host: proxy.host, port: proxy.port })
          page.go_to("https://example.com")

          expect(browser.contexts.size).to eq(1)
          expect(page.context.targets.size).to eq(1)
          expect(page.network.status).to eq(200)
          expect(page.body).to include("Example Domain")

          page = browser.create_page(proxy: { host: proxy.host, port: proxy.port })
          expect(browser.contexts.size).to eq(2)
          page.context.dispose
          expect(browser.contexts.size).to eq(1)
        end
      end

      context "with authorization" do
        let(:options) { { user: "user", password: "password" } }

        it "fails with wrong password" do
          page = browser.create_page(proxy: { host: proxy.host, port: proxy.port,
                                              user: options[:user], password: "$$" })

          if browser.headless_new?
            expect { page.go_to("https://example.com") }.to raise_error(
              Ferrum::StatusError,
              "Request to https://example.com failed (net::ERR_HTTP_RESPONSE_CODE_FAILURE)"
            )
          else
            page.go_to("https://example.com")
          end

          expect(page.network.status).to eq(407)
        end

        it "succeeds with correct password" do
          page = browser.create_page(proxy: { host: proxy.host, port: proxy.port,
                                              user: options[:user], password: options[:password] })
          page.go_to("https://example.com")

          expect(page.network.status).to eq(200)
          expect(page.body).to include("Example Domain")
        end
      end
    end
  end

  context "with pty", if: Ferrum::Utils::Platform.mri? && !Ferrum::Utils::Platform.windows? do
    require "pty"
    require "timeout"

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
