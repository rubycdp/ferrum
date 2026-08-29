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
end
