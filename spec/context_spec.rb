# frozen_string_literal: true

describe Ferrum::Context do
  describe "#create_target" do
    let(:options) { Ferrum::Browser::Options.new(timeout: 0.2, protocol_timeout: 0.01) }
    let(:client) { instance_double(Ferrum::Client, options: options) }
    let(:contexts) { instance_double(Ferrum::Contexts) }
    let(:context) { described_class.new(client, contexts, "context-id") }

    it "waits for target registration using the browser timeout" do
      allow(client).to receive(:command)
        .with("Target.createTarget", browserContextId: "context-id", url: "about:blank")
        .and_return({ "targetId" => "target-id" })

      thread = Thread.new do
        sleep 0.05
        context.add_target(params: { "targetId" => "target-id", "type" => "page", "browserContextId" => "context-id" })
      end

      target = context.create_target

      expect(target).to be_a(Ferrum::Target)
      expect(target.id).to eq("target-id")
      thread.join
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

    it "can access a second window of the same name" do
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
end
