# frozen_string_literal: true

describe Ferrum::Contexts do
  # Chrome opens `chrome://omnibox-popup.top-chrome/` (`browser_ui`) targets per
  # browser context, one or two depending on the version. Auto-attach runs with `waitForDebuggerOnStart`, so they arrive
  # paused, and nothing resumes a type we don't track: left alone they stay attached
  # and paused for the lifetime of the browser.
  describe ".new" do
    it "detaches from attached targets of a type it doesn't track" do
      untracked = Concurrent::Array.new
      detached = Concurrent::Array.new

      attached_id = browser.client.on("Target.attachedToTarget") do |params|
        type = params["targetInfo"]["type"]
        untracked << params["sessionId"] unless described_class::ALLOWED_TARGET_TYPES.include?(type)
      end
      detached_id = browser.client.on("Target.detachedFromTarget") { |params| detached << params["sessionId"] }

      browser.contexts.create.create_page

      wait(5).for { untracked.size }.to be >= 1
      wait(5).for { untracked - detached }.to be_empty
    ensure
      browser.client.off("Target.attachedToTarget", attached_id)
      browser.client.off("Target.detachedFromTarget", detached_id)
    end
  end

  describe "#default_context" do
    it "works in the browser's startup window when it came up with one", :launch do
      with_external_browser(incognito: false) do |url|
        remote = Ferrum::Browser.new(url: url)

        expect(remote.contexts.default_context).to be_implicit
        expect { remote.create_page }.not_to raise_error
      ensure
        remote&.quit
      end
    end

    it "creates a context of its own when the browser has no startup window", :launch do
      with_external_browser do |url|
        remote = Ferrum::Browser.new(url: url)
        remote.create_page

        expect(remote.contexts.default_context).not_to be_implicit

        remote.reset

        expect(remote.contexts.size).to be_zero
      ensure
        remote&.quit
      end
    end

    it "ignores contexts another client created in the same browser", :launch do
      with_external_browser do |url|
        first = Ferrum::Browser.new(url: url)
        context = first.contexts.create
        context.create_page

        second = Ferrum::Browser.new(url: url)

        expect(second.contexts.default_context).not_to be_implicit
        expect(second.contexts.default_context.id).not_to eq(context.id)
        expect { second.create_page }.not_to raise_error
      ensure
        second&.quit
        first&.quit
      end
    end
  end

  describe "#each" do
    it "yields the id and the context of every known context" do
      context = browser.contexts.create

      expect(browser.contexts.each.to_a).to include([context.id, context])
    end

    it "returns an enumerator when no block is given" do
      expect(browser.contexts.each).to be_a(Enumerator)
    end
  end

  describe "#[]" do
    it "returns the context with the given id" do
      context = browser.contexts.create

      expect(browser.contexts[context.id]).to eq(context)
    end

    it "returns nil for an unknown id" do
      expect(browser.contexts["unknown"]).to be_nil
    end
  end

  describe "#find_by" do
    it "returns the context owning the given target" do
      context = browser.contexts.create
      page = context.create_page

      expect(browser.contexts.find_by(target_id: page.target_id)).to eq(context)
    end

    it "returns nil for an unknown target" do
      expect(browser.contexts.find_by(target_id: "unknown")).to be_nil
    end
  end

  describe "#create" do
    it "creates a browser context" do
      context = browser.contexts.create

      expect(context).not_to be_implicit
      expect(browser.client.command("Target.getBrowserContexts")["browserContextIds"]).to include(context.id)
    end
  end

  describe "#dispose" do
    it "disposes the context and forgets it" do
      context = browser.contexts.create
      context.create_page

      expect(browser.contexts.dispose(context.id)).to be(true)
      expect(browser.contexts[context.id]).to be_nil
      expect(browser.client.command("Target.getBrowserContexts")["browserContextIds"]).not_to include(context.id)
    end

    it "returns nil for an unknown context" do
      expect(browser.contexts.dispose("unknown")).to be_nil
    end
  end

  describe "#size" do
    it "returns the number of known contexts" do
      size = browser.contexts.size

      browser.contexts.create

      expect(browser.contexts.size).to eq(size + 1)
    end
  end
end
