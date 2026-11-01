# frozen_string_literal: true

describe Ferrum::Context do
  describe "#windows" do
    it "waits for the window to load" do
      browser.go_to

      browser.execute <<-JS
        window.open("/slow", "popup")
      JS

      popup, = browser.windows(:last)
      expect(popup.body).to include("slow page")
      popup.close
    end

    it "opens a second window under the same name" do
      browser.go_to

      browser.execute <<-JS
        window.open("/simple", "popup")
      JS

      popup, = browser.windows(:last)
      expect(popup.body).to include("Test")
      popup.close

      sleep 0.5 # https://github.com/ChromeDevTools/devtools-protocol/issues/145

      browser.execute <<-JS
        window.open("/simple", "popup")
      JS

      sleep 0.5 # https://github.com/ChromeDevTools/devtools-protocol/issues/145

      same, = browser.windows(:last)
      expect(same.body).to include("Test")
      same.close
    end
  end

  describe "#pages" do
    it "lists pages in the order they were created" do
      pages = Array.new(10) { browser.create_page }

      expect(browser.pages.last(10).map(&:target_id)).to eq(pages.map(&:target_id))
    ensure
      pages&.each(&:close)
    end
  end

  describe "#attach_target" do
    it "reuses the session of an already attached target", :launch do
      browser = Ferrum::Browser.new(base_url: base_url,
                                    extensions: [{ source: "window.runs = (window.runs || 0) + 1" }])
      page = browser.create_page
      page.go_to
      target = browser.targets[page.target_id]
      session_id = target.session_id

      2.times { expect(browser.attach_target(target.id)).to eq(target) }
      page.refresh

      expect(target.session_id).to eq(session_id)
      expect(page.evaluate("window.runs")).to eq(1)
    ensure
      browser&.quit
    end

    it "connects to a service worker on demand, keeping it alive" do
      page.go_to
      page.evaluate(%(await navigator.serviceWorker.register("/sw.js")), timeout: 5)

      target = wait_for_target(&:service_worker?)
      browser.attach_target(target.id)

      expect(target.worker.evaluate("1 + 1")).to eq(2)
    end
  end

  describe "#workers" do
    it "returns a connected dedicated worker" do
      page.go_to

      page.execute <<~JS
        new Worker(URL.createObjectURL(new Blob(
          ["self.onmessage = () => self.postMessage(1 + 1)"],
          { type: "application/javascript" }
        )))
      JS

      target = wait_for_target(&:worker?)

      expect(target.url).to start_with("blob:")
      expect(target.connected?).to eq(true)
      expect(browser.workers).to contain_exactly(target.worker)
      expect(target.worker.evaluate("1 + 1")).to eq(2)
    end

    it "returns a connected shared worker" do
      page.go_to

      page.execute <<~JS
        new SharedWorker(URL.createObjectURL(new Blob(
          ["self.onconnect = () => {}"],
          { type: "application/javascript" }
        )))
      JS

      target = wait_for_target(&:shared_worker?)

      expect(target.connected?).to eq(true)
      expect(browser.workers).to contain_exactly(target.worker)
      expect(target.worker.evaluate("1 + 1")).to eq(2)
    end

    it "leaves out a detached worker" do
      page.go_to

      page.execute <<~JS
        new Worker(URL.createObjectURL(new Blob(
          ["self.onmessage = () => {}"],
          { type: "application/javascript" }
        )))
      JS

      target = wait_for_target(&:worker?)
      wait_for { browser.workers }.to contain_exactly(target.worker)
      page.command("Target.detachFromTarget", sessionId: target.session_id)

      wait_for { browser.workers }.to be_empty
    end
  end

  describe "#service_workers" do
    it "returns registered service workers without connecting to them" do
      page.go_to
      page.evaluate(%(await navigator.serviceWorker.register("/sw.js")), timeout: 5)

      target = wait_for_target(&:service_worker?)

      expect(target.url).to end_with("/sw.js")
      expect(target.connected?).to eq(false)
      expect(browser.service_workers).to contain_exactly(target)
    end

    it "detaches from them so Chrome can terminate them" do
      page.go_to
      page.execute(%(await navigator.serviceWorker.register("/sw.js")), timeout: 5)
      target = wait_for_target(&:service_worker?)

      wait_for do
        browser.client.command("Target.getTargets")["targetInfos"]
               .select { |info| info["type"] == "service_worker" }.map { |info| info["attached"] }
      end.to eq([false])
      expect(target.session_id).to be_nil
    end
  end
end
