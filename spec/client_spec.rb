# frozen_string_literal: true

describe Ferrum::Client do
  describe "a dead connection" do
    let(:remote) { Ferrum::Browser.new(base_url: base_url, timeout: 10, protocol_timeout: 10) }

    after { remote.quit }

    def messages
      remote.client.instance_variable_get(:@ws).messages
    end

    it "releases the commands in flight" do
      page = remote.create_page
      Thread.new do
        sleep(0.2)
        messages.close
      end
      start = Ferrum::Utils::ElapsedTime.monotonic_time

      expect { page.go_to("/really_slow") }.to raise_error(Ferrum::DeadBrowserError)
      expect(Ferrum::Utils::ElapsedTime.elapsed_time(start)).to be < 5
    end

    it "fails the commands that follow without waiting" do
      page = remote.create_page
      messages.close
      start = Ferrum::Utils::ElapsedTime.monotonic_time

      expect { page.go_to("/") }.to raise_error(Ferrum::DeadBrowserError)
      expect(Ferrum::Utils::ElapsedTime.elapsed_time(start)).to be < 1
    end
  end

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
