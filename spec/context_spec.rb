# frozen_string_literal: true

describe Ferrum::Context do
  describe "#implicit?" do
    it "returns false for a context created by Ferrum" do
      expect(browser.contexts.create).not_to be_implicit
    end

    it "returns true for the context of the browser's startup window", :launch do
      with_external_browser(incognito: false) do |url|
        remote = Ferrum::Browser.new(url: url)

        expect(remote.contexts.default_context).to be_implicit
      ensure
        remote&.quit
      end
    end
  end

  describe "#default_target" do
    it "creates a target when the context has none" do
      context = browser.contexts.create

      target = context.default_target

      expect(context.targets.values).to eq([target])
    end

    it "returns the first target of the context" do
      context = browser.contexts.create
      page = context.create_page
      context.create_page

      expect(context.default_target.id).to eq(page.target_id)
    end
  end

  describe "#cookies" do
    it "returns the cookies set by any page of the context" do
      context = browser.contexts.create
      context.create_page.go_to("/set_cookie")

      expect(context.cookies.map(&:name)).to eq(["stealth"])
      expect(browser.contexts.create.cookies.to_a).to be_empty
    end
  end

  describe "#page" do
    it "connects to the page of the default target" do
      context = browser.contexts.create

      page = context.page

      expect(page.target_id).to eq(context.default_target.id)
      expect(context.default_target).to be_connected
      expect(context.page).to equal(page)
    end
  end

  describe "#pages" do
    it "lists pages in the order they were created" do
      pages = Array.new(10) { browser.create_page }

      expect(browser.pages.last(10).map(&:target_id)).to eq(pages.map(&:target_id))
    ensure
      pages&.each(&:close)
    end

    it "returns only the pages of the targets the block selects" do
      browser.go_to
      popup = browser.wait_for_new_page! { browser.execute(%(window.open("/simple"))) }

      expect(browser.pages(&:opener_id)).to eq([popup])
    ensure
      popup&.close
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
        browser.command("Target.getTargets")["targetInfos"]
               .select { |info| info["type"] == "service_worker" }.map { |info| info["attached"] }
      end.to eq([false])
      expect(target.session_id).to be_nil
    end
  end

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

  describe "#wait_for_new_page" do
    it "returns the page opened with window.open" do
      browser.go_to

      popup = browser.wait_for_new_page { browser.execute(%(window.open("/simple"))) }

      expect(popup.body).to include("Test")
      expect(browser.pages).to include(popup)
    ensure
      popup&.close
    end

    it "returns the page opened by a link with a blank target" do
      browser.go_to
      browser.content = %(<a href="/simple" target="_blank" rel="noopener">open</a>)

      popup = browser.wait_for_new_page { browser.at_css("a").click }

      expect(popup.url).to eq(base_url("/simple"))
    ensure
      popup&.close
    end

    it "waits for the page to load" do
      browser.go_to

      popup = browser.wait_for_new_page { browser.execute(%(window.open("/slow", "popup"))) }

      expect(popup.body).to include("slow page")
    ensure
      popup&.close
    end

    it "returns the page opened under the name of a closed one" do
      browser.go_to
      browser.wait_for_new_page { browser.execute(%(window.open("/simple", "popup"))) }.close
      sleep 0.5 # https://github.com/ChromeDevTools/devtools-protocol/issues/145

      same = browser.wait_for_new_page { browser.execute(%(window.open("/simple", "popup"))) }

      expect(same.body).to include("Test")
    ensure
      same&.close
    end

    it "returns the page opened by the given opener" do
      browser.go_to
      other = browser.create_page
      other.go_to("/")

      popup = browser.wait_for_new_page(opener: other) { other.execute(%(window.open("/simple"))) }

      expect(browser.targets[popup.target_id].opener_id).to eq(other.target_id)
    ensure
      popup&.close
      other&.close
    end

    it "leaves out the pages opened by other pages than the given opener" do
      browser.go_to
      other = browser.create_page

      popup = browser.wait_for_new_page(opener: other, timeout: 0.5) { browser.execute(%(window.open("/simple"))) }

      expect(popup).to be_nil
    ensure
      browser.targets.each_value { |t| t.page.close if t.opener_id }
      other&.close
    end

    it "leaves out the pages opened in other contexts" do
      browser.go_to
      context = browser.contexts.create

      popup = context.wait_for_new_page(timeout: 0.5) { browser.execute(%(window.open("/simple"))) }

      expect(popup).to be_nil
    ensure
      browser.targets.each_value { |t| t.page.close if t.opener_id }
      context&.dispose
    end

    it "returns nil when no page opens in time" do
      expect(browser.wait_for_new_page(timeout: 0.1)).to be_nil
    end
  end

  describe "#wait_for_new_page!" do
    it "returns the page opened with window.open" do
      browser.go_to

      popup = browser.wait_for_new_page! { browser.execute(%(window.open("/simple"))) }

      expect(popup.body).to include("Test")
    ensure
      popup&.close
    end

    it "returns the page opened by the given opener" do
      browser.go_to
      other = browser.create_page
      other.go_to("/")

      popup = browser.wait_for_new_page!(opener: other) { other.execute(%(window.open("/simple"))) }

      expect(browser.targets[popup.target_id].opener_id).to eq(other.target_id)
    ensure
      popup&.close
      other&.close
    end

    it "raises when no page opens in time" do
      expect { browser.wait_for_new_page!(timeout: 0.1) }.to raise_error(Ferrum::TimeoutError)
    end
  end

  describe "#create_page" do
    it "creates a connected page in the context" do
      context = browser.contexts.create

      page = context.create_page

      expect(page.context_id).to eq(context.id)
      expect(context.targets[page.target_id]).to be_connected
      expect(context.pages).to eq([page])
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

  describe "#find_target" do
    it "returns the first target the block matches" do
      context = browser.contexts.create
      page = context.create_page

      expect(context.find_target { |target| target.id == page.target_id }.id).to eq(page.target_id)
    end

    it "returns nil when no target matches" do
      context = browser.contexts.create
      context.create_page

      expect(context.find_target { false }).to be_nil
    end
  end

  describe "#dispose" do
    it "disposes the context and its targets" do
      context = browser.contexts.create
      page = context.create_page

      expect(context.dispose).to be(true)
      expect(browser.contexts[context.id]).to be_nil
      expect(browser.command("Target.getBrowserContexts")["browserContextIds"]).not_to include(context.id)
      target_ids = browser.command("Target.getTargets")["targetInfos"].map { |info| info["targetId"] }
      expect(target_ids).not_to include(page.target_id)
    end

    it "leaves the context of the browser's startup window alone", :launch do
      with_external_browser(incognito: false) do |url|
        remote = Ferrum::Browser.new(url: url)
        context = remote.contexts.default_context

        expect(context.dispose).to be_nil
        expect(remote.contexts[context.id]).to eq(context)
      ensure
        remote&.quit
      end
    end
  end

  describe "#target" do
    it "returns the target with the given id" do
      context = browser.contexts.create
      page = context.create_page

      expect(context.target(page.target_id).page).to be(page)
    end

    it "returns nil for a target of another context" do
      context = browser.contexts.create

      expect(context.target(browser.contexts.create.create_page.target_id)).to be_nil
    end
  end

  describe "#target?" do
    it "returns true for a target of the context" do
      context = browser.contexts.create

      expect(context.target?(context.create_page.target_id)).to be(true)
    end

    it "returns false for a target of another context" do
      context = browser.contexts.create

      expect(context.target?(browser.contexts.create.create_page.target_id)).to be(false)
    end
  end
end
