# frozen_string_literal: true

describe Ferrum::Contexts do
  # Chrome opens two `chrome://omnibox-popup.top-chrome/` (`browser_ui`) targets per
  # browser context. Auto-attach runs with `waitForDebuggerOnStart`, so they arrive
  # paused, and nothing resumes a type we don't track: left alone they stay attached
  # and paused for the lifetime of the browser.
  it "detaches from attached targets of a type it doesn't track" do
    untracked = Concurrent::Array.new
    detached = Concurrent::Array.new

    attached_id = browser.client.on("Target.attachedToTarget") do |params|
      type = params["targetInfo"]["type"]
      untracked << params["sessionId"] unless described_class::ALLOWED_TARGET_TYPES.include?(type)
    end
    detached_id = browser.client.on("Target.detachedFromTarget") { |params| detached << params["sessionId"] }

    browser.contexts.create.create_page

    wait(5).for { untracked.size }.to be >= 2
    wait(5).for { untracked - detached }.to be_empty
  ensure
    browser.client.off("Target.attachedToTarget", attached_id)
    browser.client.off("Target.detachedFromTarget", detached_id)
  end

  describe "#default_context" do
    it "works in the browser's startup window when it came up with one" do
      with_external_browser(incognito: false) do |url|
        remote = Ferrum::Browser.new(url: url)

        expect(remote.contexts.default_context).to be_implicit
        expect { remote.create_page }.not_to raise_error
      ensure
        remote&.quit
      end
    end

    it "creates a context of its own when the browser has no startup window" do
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

    it "ignores contexts another client created in the same browser" do
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
end
