# frozen_string_literal: true

require "logger"
require "ferrum/proxy"

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

      it "supports custom chrome path", :launch do
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

    context ":logger argument" do
      it "supports :logger argument", :launch do
        browser = Ferrum::Browser.new(logger: logger)
        browser.go_to(base_url("/console_log"))

        wait_for { logger.string }.to include("Runtime.consoleAPICalled")
        expect(logger.string).to include("DevTools listening on")
        expect(logger.string).not_to include("[log] Hello world")
      ensure
        browser&.quit
      end

      it "writes to a Logger at debug level", :launch do
        browser = Ferrum::Browser.new(logger: Logger.new(logger, level: :debug))
        browser.go_to(base_url("/console_log"))

        expect(logger.string).to include("DEBUG -- ferrum:browser: DevTools listening on")
        expect(logger.string).to include("DEBUG -- ferrum:protocol: \n\n▶")
      ensure
        browser&.quit
      end

      it "writes nothing to a Logger above debug level", :launch do
        browser = Ferrum::Browser.new(logger: Logger.new(logger, level: :info))
        browser.go_to(base_url("/console_log"))

        expect(logger.string).to be_empty
      ensure
        browser&.quit
      end

      it "logs to $stdout with FERRUM_LOG", :launch do
        with_env("FERRUM_LOG" => "browser") do
          expect do
            Ferrum::Browser.new.quit
          end.to output(/DevTools listening on/).to_stdout
        end
      end

      it "logs nothing with FERRUM_LOG=0", :launch do
        with_env("FERRUM_LOG" => "0") do
          browser = Ferrum::Browser.new(logger: logger)
          browser.go_to(base_url("/console_log"))

          expect(logger.string).to be_empty
        ensure
          browser&.quit
        end
      end

      it "logs everything with the deprecated FERRUM_DEBUG", :launch do
        with_env("FERRUM_DEBUG" => "true") do
          browser = Ferrum::Browser.new(logger: logger)
          browser.go_to(base_url("/console_log"))

          expect(logger.string).to include("Page.navigate")
          expect(logger.string).to include("DevTools listening on")
        ensure
          browser&.quit
        end
      end

      it "leaves out the channels excluded in FERRUM_LOG", :launch do
        with_env("FERRUM_LOG" => "*,-browser") do
          browser = Ferrum::Browser.new(logger: logger)
          browser.go_to(base_url("/console_log"))

          expect(logger.string).to include("Page.navigate")
          expect(logger.string).not_to include("DevTools listening on")
        ensure
          browser&.quit
        end
      end

      it "logs only CDP messages matching FERRUM_LOG", :launch do
        with_env("FERRUM_LOG" => "Page.navigate") do
          browser = Ferrum::Browser.new(logger: logger)
          browser.go_to(base_url("/console_log"))

          expect(logger.string).to include(%("method":"Page.navigate"))
          expect(logger.string).to match(/"result":\{"frameId":"\h+","loaderId"/)
          expect(logger.string).not_to include("Runtime.")
          expect(logger.string).not_to include("DevTools listening on")
        ensure
          browser&.quit
        end
      end

      it "leaves out CDP messages excluded in FERRUM_LOG", :launch do
        with_env("FERRUM_LOG" => "protocol,-Network.*,-Page.navigate") do
          browser = Ferrum::Browser.new(logger: logger)
          browser.go_to(base_url("/console_log"))

          wait_for { logger.string }.to include("Runtime.consoleAPICalled")
          expect(logger.string).not_to include("Network.")
          expect(logger.string).not_to include("Page.navigate")
          expect(logger.string).not_to match(/"result":\{"frameId":"\h+","loaderId"/)
        ensure
          browser&.quit
        end
      end

      it "writes CDP messages as JSON alone with FERRUM_LOG_FORMAT=json", :launch do
        with_env("FERRUM_LOG" => "protocol", "FERRUM_LOG_FORMAT" => "json") do
          def logger.tty? = true
          browser = Ferrum::Browser.new(logger: logger)
          browser.go_to(base_url("/console_log"))

          messages = logger.string.lines.map { |line| JSON.parse(line) }
          expect(messages).to include(a_hash_including("method" => "Page.navigate", "params" => { "url" => base_url("/console_log") }))
          expect(messages).to include(a_hash_including("id" => a_kind_of(Integer), "result" => a_hash_including("frameId")))
        ensure
          browser&.quit
        end
      end

      it "annotates CDP messages with FERRUM_LOG_FORMAT=annotated", :launch do
        with_env("FERRUM_LOG_FORMAT" => "annotated") do
          browser = Ferrum::Browser.new(logger: logger)
          browser.go_to(base_url("/console_log"))

          expect(logger.string).to match(%r{^▶ \d+\.\d{3} #\d+ Page\.navigate \{"url":"http://[^"]+/console_log"\} @\h{8}$})
          id = logger.string[/▶ \S+ #(\d+) Page\.navigate/, 1]
          expect(logger.string).to match(/^    ◀ \d+\.\d{3} ##{id} Page\.navigate \d+ms \{"frameId":"\h+",.+\} @\h{8}$/)
          wait_for { logger.string }.to match(/^    ◀ \d+\.\d{3} Runtime\.consoleAPICalled \{"type":"log"/)
        ensure
          browser&.quit
        end
      end

      it "colors protocol lines written to a terminal", :launch do
        def logger.tty? = true
        browser = Ferrum::Browser.new(logger: logger)
        browser.go_to(base_url("/console_log"))

        expect(logger.string).to include(%("method":"\e[1mPage.navigate\e[0m"))
        expect(logger.string).to include("\e[36m▶\e[0m")
      ensure
        browser&.quit
      end

      it "writes plain text when not writing to a terminal", :launch do
        browser = Ferrum::Browser.new(logger: logger)
        browser.go_to(base_url("/console_log"))

        expect(logger.string).to include("Page.navigate")
        expect(logger.string).not_to include("\e[")
      ensure
        browser&.quit
      end

      it "colors lines written anywhere with FERRUM_LOG_COLOR=always", :launch do
        with_env("FERRUM_LOG_COLOR" => "always") do
          browser = Ferrum::Browser.new(logger: logger)
          browser.go_to(base_url("/console_log"))

          expect(logger.string).to include("\e[36m▶\e[0m")
        ensure
          browser&.quit
        end
      end

      it "writes plain text to a terminal with FERRUM_LOG_COLOR=never", :launch do
        with_env("FERRUM_LOG_COLOR" => "never") do
          def logger.tty? = true
          browser = Ferrum::Browser.new(logger: logger)
          browser.go_to(base_url("/console_log"))

          expect(logger.string).to include("Page.navigate")
          expect(logger.string).not_to include("\e[")
        ensure
          browser&.quit
        end
      end

      it "keeps the browser working when the logger fails", :launch do
        broken = Object.new
        def broken.puts(*) = raise(IOError, "closed stream")
        browser = nil

        expect do
          browser = Ferrum::Browser.new(logger: broken)
          browser.go_to(base_url("/console_log"))
        end.to output(/couldn't write to the logger, IOError: closed stream/).to_stderr
        expect(browser.evaluate("1 + 1")).to eq(2)
      ensure
        browser&.quit
      end

      it "logs CDP messages nested deeper than JSON's default limit", :launch do
        browser = Ferrum::Browser.new(logger: logger)
        browser.go_to(base_url("/deeply_nested"))

        expect(browser.evaluate(%(document.getElementById("text"))).text).to eq("text")
        expect(logger.string).to include("DOM.setChildNodes")
      ensure
        browser&.quit
      end

      it "shortens long strings in logged CDP messages", :launch, skip: Ferrum::Log::VALUE_LENGTH.zero? do
        browser = Ferrum::Browser.new(logger: logger)
        browser.go_to(base_url("/console_log"))
        screenshot = browser.screenshot(encoding: :base64)

        expect(logger.string).not_to include(screenshot)
        expect(logger.string).to include("#{screenshot[0, Ferrum::Log::VALUE_LENGTH]}... (" \
                                         "#{screenshot.size - Ferrum::Log::VALUE_LENGTH} more characters)")
      ensure
        browser&.quit
      end
    end

    it "keeps the output of the browser process", :launch do
      browser = Ferrum::Browser.new

      expect(browser.process.output.lines).to include(a_string_starting_with("DevTools listening on"))
    ensure
      browser&.quit
    end

    it "supports :ignore_default_browser_options argument", :launch do
      defaults = Ferrum::Browser::Options::Chrome.options.except("mute-audio")
      browser = Ferrum::Browser.new(ignore_default_browser_options: true,
                                    browser_options: defaults.merge("no-sandbox" => nil))
      browser.go_to(base_url("/console_log"))

      flags = browser.process.command.to_a
      expect(flags).not_to include("--mute-audio")
      expect(flags).to include("--no-sandbox")
      expect(flags).to include(a_string_starting_with("--remote-debugging-port="))
      expect(flags).to include(a_string_starting_with("--user-data-dir="))
    ensure
      browser&.quit
    end

    it "keeps the same-origin policy by default" do
      browser.go_to("/frames")

      result = browser.evaluate(<<~JS)
        await fetch("http://localhost:" + location.port + "/headers").then(() => "read", () => "blocked")
      JS

      expect(result).to eq("blocked")
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
      it "extends the browser's world with files", :launch do
        browser = Ferrum::Browser.new(base_url: base_url,
                                      extensions: [File.expand_path("support/geolocation.js", __dir__)])

        browser.go_to("/requiring_custom_extension")

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

      it "extends the browser's world with source", :launch do
        browser = Ferrum::Browser.new(base_url: base_url,
                                      extensions: [{ source: "window.secret = 'top'" }])

        browser.go_to("/requiring_custom_extension")

        expect(browser.evaluate(%(window.secret))).to eq("top")
      ensure
        browser&.quit
      end

      it "extends a popup's world before its scripts run", :launch do
        browser = Ferrum::Browser.new(base_url: base_url,
                                      extensions: [File.expand_path("support/geolocation.js", __dir__)])
        browser.go_to

        browser.execute(%(window.open("/requiring_custom_extension", "popup")))
        popup, = browser.windows(:last)

        expect(popup.at_css("#location").text).to eq("1,-1")
      ensure
        browser&.quit
      end

      it "extends an out-of-process iframe's world before its scripts run", :launch do
        report = <<~JS
          if (window !== top) {
            addEventListener("load", () => parent.postMessage(document.getElementById("location").textContent, "*"));
          }
        JS
        browser = Ferrum::Browser.new(base_url: base_url,
                                      browser_options: { "site-per-process" => nil },
                                      extensions: [File.expand_path("support/geolocation.js", __dir__), { source: report }])
        browser.go_to
        browser.execute(<<~JS)
          addEventListener("message", (event) => { window.iframeLocation = event.data });
          document.body.innerHTML = `<iframe src="http://localhost:${location.port}/requiring_custom_extension">`;
        JS

        iframe_location = Ferrum::Utils::Attempt.with_retry(errors: RuntimeError, max: 50, wait: 0.1) do
          browser.evaluate("window.iframeLocation") || raise("no message from the iframe yet")
        end

        expect(browser.targets.values.map(&:type)).to include("iframe")
        expect(iframe_location).to eq("1,-1")
      ensure
        browser&.quit
      end

      it "errors when extension is unavailable", :launch do
        expect do
          Ferrum::Browser.new(extensions: [File.expand_path("../support/non_existent.js", __dir__)])
        end.to raise_error(Errno::ENOENT)
      end
    end

    describe "#add_extension" do
      it "extends the world of pages opened afterwards", :launch do
        browser = Ferrum::Browser.new(base_url: base_url)

        browser.add_extension(source: "window.secret = 'top'")
        page = browser.create_page
        page.go_to("/requiring_custom_extension")

        expect(page.evaluate("window.secret")).to eq("top")
      ensure
        browser&.quit
      end

      it "errors when extension is unavailable", :launch do
        browser = Ferrum::Browser.new

        expect do
          browser.add_extension(File.expand_path("../support/non_existent.js", __dir__))
        end.to raise_error(Errno::ENOENT)
      ensure
        browser&.quit
      end
    end

    it "supports :port argument", :launch do
      browser = Ferrum::Browser.new(port: 12_345)
      browser.go_to(base_url)

      expect { TCPServer.new("127.0.0.1", 12_345) }.to raise_error(Errno::EADDRINUSE)
    ensure
      browser&.quit
    end

    it "supports :url argument", :launch do
      with_external_browser do |url, _process|
        browser = Ferrum::Browser.new(url: url)
        browser.go_to(base_url)
        expect(browser.body).to include("Hello world!")
        expect(browser.default_user_agent).to include("Chrome")
      ensure
        browser&.quit
      end
    end

    def with_token_authenticated_proxy(browser_url, token:, json_version: :full)
      browser_url = Addressable::URI.parse(browser_url)
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]

      acceptor = Thread.new do
        loop { Thread.new(server.accept) { |socket| proxy_request(socket, browser_url, token, port, json_version) } }
      rescue IOError, Errno::EBADF
        nil
      end

      yield "http://127.0.0.1:#{port}?token=#{token}"
    ensure
      acceptor&.kill
      server&.close
    end

    def proxy_request(socket, browser_url, token, port, json_version)
      request = socket.gets.to_s

      if !request.include?("token=#{token}")
        socket.print(proxy_unauthorized)
      elsif request.start_with?("GET /json/version")
        socket.print(proxy_json_version(browser_url, port, json_version)) unless json_version == :missing
      else
        proxy_tunnel(socket, request, browser_url)
      end
    ensure
      socket.close unless socket.closed?
    end

    def proxy_unauthorized
      body = "<html>401 Unauthorized</html>"
      "HTTP/1.1 401 Unauthorized\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
    end

    def proxy_json_version(browser_url, port, json_version)
      version = JSON.parse(Net::HTTP.get(URI(browser_url.join("/json/version").to_s)))
      version.delete("User-Agent") if json_version == :without_user_agent
      path = Addressable::URI.parse(version["webSocketDebuggerUrl"]).path
      body = version.merge("webSocketDebuggerUrl" => "ws://0.0.0.0:#{port}#{path}").to_json
      "HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
    end

    def proxy_tunnel(socket, request, browser_url)
      upstream = TCPSocket.new(browser_url.host, browser_url.port)
      upstream.print(request.sub(/\?token=[^ ]*/, ""))

      [[socket, upstream], [upstream, socket]].map do |from, to|
        Thread.new do
          loop { to.write(from.readpartial(16 * 1024)) }
        rescue IOError, Errno::ECONNRESET, Errno::EPIPE, Errno::EBADF
          nil
        end
      end.each(&:join)
    ensure
      upstream&.close
    end

    it "supports :url argument with a query string", :launch do
      with_external_browser do |url, _process|
        with_token_authenticated_proxy(url, token: "secret") do |proxy_url|
          browser = Ferrum::Browser.new(url: proxy_url)
          browser.go_to(base_url)

          expect(browser.body).to include("Hello world!")
          expect(browser.process.ws_url.authority).to eq(Addressable::URI.parse(proxy_url).authority)
          expect(browser.process.ws_url.query).to eq("token=secret")
        ensure
          browser&.quit
        end
      end
    end

    it "adds headers when /json/version has no User-Agent", :launch do
      with_external_browser do |url, _process|
        with_token_authenticated_proxy(url, token: "secret", json_version: :without_user_agent) do |proxy_url|
          browser = Ferrum::Browser.new(url: proxy_url, base_url: base_url)
          browser.headers.add({ "X-Custom" => "1" })
          browser.go_to("/headers")

          expect(browser.default_user_agent).to include("Chrome")
          expect(browser.body).to include("X_CUSTOM: 1")
        ensure
          browser&.quit
        end
      end
    end

    it "raises when :url doesn't answer with a websocket url", :launch do
      with_external_browser do |url, _process|
        with_token_authenticated_proxy(url, token: "secret") do |proxy_url|
          unauthorized = proxy_url.sub("secret", "wrong")

          expect { Ferrum::Browser.new(url: unauthorized) }
            .to raise_error(Ferrum::NoWebSocketUrlError, /#{Regexp.escape(unauthorized)}.* answered 401 Unauthorized/)
        end
      end
    end

    it "supports :ws_url argument", :launch do
      with_external_browser do |url, _process|
        browser = Ferrum::Browser.new(ws_url: web_socket_debugger_url(url))
        browser.go_to(base_url)
        expect(browser.body).to include("Hello world!")
        expect(browser.default_user_agent).to include("Chrome")
      ensure
        browser&.quit
      end
    end

    it "supports :ws_url argument without asking /json/version", :launch do
      with_external_browser do |url, _process|
        with_token_authenticated_proxy(url, token: "secret", json_version: :missing) do |proxy_url|
          path = Addressable::URI.parse(web_socket_debugger_url(url)).path
          ws_url = Addressable::URI.parse(proxy_url).merge(scheme: "ws", path: path).to_s
          browser = Ferrum::Browser.new(ws_url: ws_url, base_url: base_url)
          browser.go_to("/")

          expect(browser.body).to include("Hello world!")
          expect(browser.default_user_agent).to include("Chrome")
        ensure
          browser&.quit
        end
      end
    end

    it "supports :host argument", skip: ENV["BROWSER_TEST_HOST"].nil? do
      # Use custom host "pointing" to localhost in /etc/hosts or iptables for this.
      # https://superuser.com/questions/516208/how-to-change-ip-address-to-point-to-localhost
      #
      # Chrome no longer supports binding its remote debugging endpoint to a custom
      # address (it always listens on 127.0.0.1), so this only verifies Ferrum talks
      # to Chrome through the requested host, not that Chrome itself binds to it.
      browser = Ferrum::Browser.new(host: ENV.fetch("BROWSER_TEST_HOST"), port: 12_345)
      browser.go_to(base_url)

      expect(browser.process.host).to eq(ENV.fetch("BROWSER_TEST_HOST"))
    ensure
      browser&.quit
    end

    context ":proxy argument" do
      let(:options) { {} }
      let(:proxy) { Ferrum::Proxy.start(**options) }

      after { proxy.stop }

      context "without authorization" do
        it "works without authorization", :launch do
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

        it "works with right password", :launch do
          browser = Ferrum::Browser.new(
            proxy: { host: proxy.host, port: proxy.port, **options }
          )

          browser.go_to("https://example.com")
          expect(browser.network.status).to eq(200)
          expect(browser.body).to include("Example Domain")
        ensure
          browser&.quit
        end

        it "breaks with wrong password", :launch do
          browser = Ferrum::Browser.new(
            proxy: { host: proxy.host, port: proxy.port, user: "u1", password: "p1" }
          )

          expect { browser.go_to("https://example.com") }.to raise_error(
            Ferrum::StatusError,
            "Request to https://example.com failed (net::ERR_HTTP_RESPONSE_CODE_FAILURE)"
          )
          expect(browser.network.status).to eq(407)
        ensure
          browser&.quit
        end

        it "lets requests be aborted", :launch do
          browser = Ferrum::Browser.new(
            proxy: { host: proxy.host, port: proxy.port, **options }
          )
          browser.network.intercept
          browser.on(:request) { |request| request.match?(/example\.com/) ? request.abort : request.continue }

          expect { browser.go_to("https://example.com") }.to raise_error(
            Ferrum::StatusError,
            "Request to https://example.com failed (net::ERR_BLOCKED_BY_CLIENT)"
          )
        ensure
          browser&.quit
        end

        it "supports blacklist", :launch do
          browser = Ferrum::Browser.new(
            proxy: { host: proxy.host, port: proxy.port, **options }
          )
          browser.network.blacklist = [/example\.com/]

          expect { browser.go_to("https://example.com") }.to raise_error(
            Ferrum::StatusError,
            "Request to https://example.com failed (net::ERR_BLOCKED_BY_CLIENT)"
          )
        ensure
          browser&.quit
        end
      end

      context "with rotation" do
        let(:upstream) { Ferrum::Proxy.start(user: "user", password: "pa$$") }

        after { upstream.stop }

        it "forwards connections to the upstream proxy in a new context", :launch do
          browser = Ferrum::Browser.new(
            proxy: { host: proxy.host, port: proxy.port }
          )

          proxy.rotate(host: upstream.host, port: upstream.port, user: "user", password: "pa$$")
          browser.create_page(new_context: true) do |page|
            page.go_to("https://example.com")
            expect(page.network.status).to eq(200)
            expect(page.body).to include("Example Domain")
          end

          proxy.rotate(host: upstream.host, port: upstream.port, user: "user", password: "wrong")
          browser.create_page(new_context: true) do |page|
            expect { page.go_to("https://example.com") }.to raise_error(
              Ferrum::StatusError, /ERR_TUNNEL_CONNECTION_FAILED/
            )
          end
        ensure
          browser&.quit
        end
      end
    end

    it "supports :pending_connection_errors argument", :launch do
      browser = Ferrum::Browser.new(base_url: base_url, pending_connection_errors: true, timeout: 0.5)

      expect { browser.go_to("/really_slow") }.to raise_error(Ferrum::PendingConnectionsError)
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

      after { browser.quit }

      context "with absolute path" do
        let(:save_path) { "/tmp/ferrum-downloads" }

        it "saves an attachment" do
          browser.go_to("/#{filename}")
          browser.downloads.wait

          expect(File.exist?("#{save_path}/#{filename}")).to be true
        ensure
          FileUtils.rm_rf(save_path)
        end
      end

      context "with local path" do
        let(:save_path) { "spec/tmp" }

        it "raises an error", :launch do
          expect do
            browser.go_to("/#{filename}")
          end.to raise_error(Ferrum::Error, "supply absolute path for `:save_path` option")
        end
      end
    end

    context "with error on initialize" do
      it "stops process if an error is raised during process start", :launch do
        process = Ferrum::Browser::Process.new(Ferrum::Browser::Options.new(process_timeout: 0))
        allow(Ferrum::Browser::Process).to receive(:new).and_return(process)
        expect { Ferrum::Browser.new }.to raise_error(Ferrum::ProcessTimeoutError)
        expect(process.pid).to be(nil)
      end

      it "stops process if an error is raised during client creation", :launch do
        process = Ferrum::Browser::Process.new(Ferrum::Browser::Options.new)
        allow(Ferrum::Browser::Process).to receive(:new).and_return(process)

        error = StandardError.new
        allow(Ferrum::Client).to receive(:new).and_raise(error)

        expect { Ferrum::Browser.new }.to raise_error(error)
        expect(process.pid).to be(nil)
      end

      it "stops process if an error is raised during contexts creation", :launch do
        process = Ferrum::Browser::Process.new(Ferrum::Browser::Options.new)
        allow(Ferrum::Browser::Process).to receive(:new).and_return(process)

        error = StandardError.new
        allow(Ferrum::Contexts).to receive(:new).and_raise(error)

        expect { Ferrum::Browser.new }.to raise_error(error)
        expect(process.pid).to be(nil)
      end
    end
  end

  describe "#crash" do
    it "works after crash with explicit restart" do
      expect { browser.crash }.to raise_error(Ferrum::DeadBrowserError)

      browser.restart
      browser.go_to

      expect(browser.body).to include("Hello world")
    end
  end

  describe "#close" do
    it "works after crash with explicit restart" do
      browser.go_to

      expect { browser.close }.not_to raise_error
      sleep 2
      expect { browser.go_to }.to raise_error(Ferrum::DeadBrowserError)

      browser.restart
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
    it "stops silently before go_to call", :launch do
      browser = Ferrum::Browser.new
      expect { browser.quit }.not_to raise_error
    ensure
      browser&.quit
    end

    it "supports stopping the session", :launch, skip: Ferrum::Utils::Platform.windows? do
      browser = Ferrum::Browser.new
      pid = browser.process.pid

      expect(Process.kill(0, pid)).to eq(1)
      browser.quit

      expect { Process.kill(0, pid) }.to raise_error(Errno::ESRCH)
    end

    it "returns immediately with wait: false, finishing cleanup once the returned thread is joined", :launch, skip: Ferrum::Utils::Platform.windows? do
      browser = Ferrum::Browser.new
      pid = browser.process.pid

      start = Ferrum::Utils::ElapsedTime.monotonic_time
      thread = browser.quit(wait: false)
      elapsed = Ferrum::Utils::ElapsedTime.monotonic_time - start

      expect(thread).to be_a(Thread)
      expect(elapsed).to be < 1

      thread.join

      expect { Process.kill(0, pid) }.to raise_error(Errno::ESRCH)
    end
  end

  describe "#restart" do
    it "blocks until the old process is confirmed dead before returning", :launch, skip: Ferrum::Utils::Platform.windows? do
      browser = Ferrum::Browser.new
      old_pid = browser.process.pid

      browser.restart

      expect { Process.kill(0, old_pid) }.to raise_error(Errno::ESRCH)
      expect(browser.process.pid).not_to eq(old_pid)
    ensure
      browser&.quit
    end
  end

  describe "#resize" do
    it "allows the viewport to be resized" do
      browser.go_to
      browser.resize(width: 200, height: 400)
      expect(browser.viewport_size).to eq([200, 400])
    end

    it "resizes windows" do
      browser.go_to

      expect(browser.targets.size).to eq(1)

      browser.execute <<-JS
        window.open("/simple", "popup1")
      JS

      sleep 0.1

      browser.execute <<-JS
        window.open("/simple", "popup2")
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
          expect(browser.viewport_size).to eq([1024, 681])
          browser.go_to(path)
          browser.resize(fullscreen: true)
          expect(browser.viewport_size).to eq(viewport_size)
        end
      end

      include_examples "resize viewport by fullscreen" do
        let(:path) { "/custom_html_size" }
        let(:viewport_size) { [1280, 1024] }
      end

      include_examples "resize viewport by fullscreen" do
        let(:path) { "/custom_html_size_100%" }
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

  describe "#targets" do
    it "lists the open windows" do
      browser.go_to

      browser.execute <<~JS
        window.open("/simple", "popup")
      JS

      sleep 0.1

      expect(browser.targets.size).to eq(2)

      browser.execute <<~JS
        window.open("/simple", "popup2")
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
      page.go_to("/simple")

      expect(browser.contexts.size).to eq(1)
      expect(browser.targets.size).to eq(1)
    end

    it "supports calling with block" do
      expect(browser.contexts.size).to eq(0)
      expect(browser.targets.size).to eq(0)

      browser.create_page do |page|
        page.go_to("/simple")
      end

      sleep 1 # It may take longer to close the target
      expect(browser.contexts.size).to eq(1)
      expect(browser.targets.size).to eq(0)
    end

    context "with :new_context" do
      it "supports calling without block" do
        expect(browser.contexts.size).to eq(0)

        page = browser.create_page(new_context: true)
        page.go_to("/simple")

        context = browser.contexts[page.context_id]
        expect(browser.contexts.size).to eq(1)
        expect(context.targets.size).to eq(1)

        context.create_page
        expect(context.targets.size).to eq(2)
        context.dispose
        expect(browser.contexts.size).to eq(0)
      end

      it "closes page successfully" do
        expect(browser.contexts.size).to eq(0)

        page = browser.create_page(new_context: true)
        context = browser.contexts[page.context_id]
        page.go_to("/simple")
        page.close

        expect(browser.contexts.size).to eq(1)
        expect(context.targets.size).to be_between(0, 1) # needs some time to close target

        context.dispose
        expect(browser.contexts.size).to eq(0)
      end

      it "supports calling with block" do
        expect(browser.contexts.size).to eq(0)

        browser.create_page(new_context: true) do |page|
          page.go_to("/simple")
        end

        expect(browser.contexts.size).to eq(0)
      end

      it "propagates the original error when context creation fails inside the block form" do
        original_error = Ferrum::DeadBrowserError.new("simulated browser death")
        allow(browser.contexts).to receive(:create).and_raise(original_error)

        expect do
          browser.create_page(new_context: true) do |page|
            page.go_to("/simple")
          end
        end.to raise_error(Ferrum::DeadBrowserError, "simulated browser death")
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
          expect(browser.contexts[page.context_id].targets.size).to eq(1)
          expect(page.network.status).to eq(200)
          expect(page.body).to include("Example Domain")

          page = browser.create_page(proxy: { host: proxy.host, port: proxy.port })
          expect(browser.contexts.size).to eq(2)
          browser.contexts[page.context_id].dispose
          expect(browser.contexts.size).to eq(1)
        end
      end

      context "with authorization" do
        let(:options) { { user: "user", password: "password" } }

        it "fails with wrong password" do
          page = browser.create_page(proxy: { host: proxy.host, port: proxy.port,
                                              user: options[:user], password: "$$" })

          expect { page.go_to("https://example.com") }.to raise_error(
            Ferrum::StatusError,
            "Request to https://example.com failed (net::ERR_HTTP_RESPONSE_CODE_FAILURE)"
          )
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

  describe "#debug_url" do
    it "parses the devtools frontend url correctly when devtoolsFrontendUrl is relative", :launch do
      browser = Ferrum::Browser.new(port: 12_345)
      uri = instance_double(URI)

      allow(browser).to receive(:URI).with("http://127.0.0.1:12345/json").and_return(uri)
      allow(Net::HTTP).to receive(:get).with(uri).and_return(%([{"devtoolsFrontendUrl":"/works"}]))

      expect(browser.send(:debug_url)).to eq("http://127.0.0.1:12345/works")
    end

    it "parses the devtools frontend url correctly when devtoolsFrontendUrl is fully qualified", :launch do
      browser = Ferrum::Browser.new(port: 12_346)
      uri = instance_double(URI)

      allow(browser).to receive(:URI).with("http://127.0.0.1:12346/json").and_return(uri)
      allow(Net::HTTP).to receive(:get).with(uri).and_return(
        %([{"devtoolsFrontendUrl":"https://chrome-devtools-frontend.appspot.com/serve_rev?ws=123"}])
      )

      expect(browser.send(:debug_url)).to eq("https://chrome-devtools-frontend.appspot.com/serve_rev?ws=123")
    end
  end

  context "with pty", :launch, if: Ferrum::Utils::Platform.mri? && !Ferrum::Utils::Platform.windows? do
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
