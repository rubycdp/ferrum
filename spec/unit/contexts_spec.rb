# frozen_string_literal: true

describe Ferrum::Contexts do
  describe "#reset" do
    it "forgets a context whose disposal fails and still disposes the others" do
      stuck = browser.contexts.create
      other = browser.contexts.create
      allow(browser.client).to receive(:command).and_call_original
      allow(browser.client).to receive(:command)
        .with("Target.disposeBrowserContext", browserContextId: stuck.id)
        .and_raise(Ferrum::TimeoutError)

      expect { browser.reset }.to raise_error(Ferrum::TimeoutError)
      expect(browser.contexts[stuck.id]).to be_nil
      expect(browser.contexts[other.id]).to be_nil
      expect(browser.client.command("Target.getBrowserContexts")["browserContextIds"]).not_to include(other.id)

      allow(browser.client).to receive(:command)
        .with("Target.disposeBrowserContext", browserContextId: stuck.id)
        .and_raise(Ferrum::BrowserError, { "message" => "Disposal of browser context #{stuck.id} is already pending" })

      expect { browser.reset }.not_to raise_error
    end
  end
end
