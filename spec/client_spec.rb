# frozen_string_literal: true

describe Ferrum::Client do
  describe "event callbacks" do
    let(:remote) { Ferrum::Browser.new(base_url: base_url, timeout: 3, protocol_timeout: 3) }

    after { remote.quit }

    it "keeps dispatching events when a callback raises" do
      page = remote.create_page

      expect do
        remote.client.on("Target.targetCreated") { raise Ferrum::TimeoutError }

        2.times { remote.create_page }
        page.go_to("/")
      end.to output(/Target.targetCreated callback raised Ferrum::TimeoutError/).to_stderr

      expect(page.body).to include("Hello world!")
    end
  end
end
