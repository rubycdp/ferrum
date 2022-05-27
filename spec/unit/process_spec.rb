# frozen_string_literal: true

module Ferrum
  class Browser
    describe Process do
      subject { Browser.new(port: 6000, host: "127.0.0.1") }

      unless Utils::Platform.windows?
        it "forcibly kills the child if it does not respond to SIGTERM" do
          allow(::Process).to receive_messages(spawn: 5678)
          allow(::Process).to receive(:wait).and_return(nil)
          allow(Client).to receive(:new).and_return(double.as_null_object)

          allow_any_instance_of(Process).to receive(:parse_ws_url)

          subject.send(:start)

          expect(::Process).to receive(:kill).with("USR1", 5678).ordered
          expect(::Process).to receive(:kill).with("KILL", 5678).ordered

          subject.quit
        end
      end

      it "hooks existing Chrome instance by websocket" do
        version_url_response = {
          "Browser" => "HeadlessChrome/101.0.4951.64",
          "Protocol-Version" => "1.3",
          "User-Agent" => "Mozilla/5.0",
          "V8-Version" => "10.1.124.12",
          "WebKit-Version" => "537.36 (@d1daa9897e1bc1d507d6be8f2346e377e5505905)",
          "webSocketDebuggerUrl" => "ws://127.0.0.1:45537/devtools/browser/4b78acad-9168-4e68-99aa-0030a467071e"
        }
        with_external_browser do |url|
          ws_url = "ws://#{url.host}:#{url.port}"
          expect(::Net::HTTP).to receive(:get).and_return(version_url_response.to_json)
          browser = Browser.new(ws_url: ws_url)
          expect(browser.default_user_agent).to be_nil
        ensure
          browser&.quit
        end
      end

      context "env variables" do
        subject { Browser.new(env: { "LD_PRELOAD" => "some.so" }) }

        it "passes through env" do
          allow(::Process).to receive(:wait).and_return(nil)
          allow(Client).to receive(:new).and_return(double.as_null_object)

          allow(::Process).to receive(:spawn).with({ "LD_PRELOAD" => "some.so" }, any_args)

          allow_any_instance_of(Process).to receive(:parse_ws_url)

          subject.send(:start)
          subject.quit
        end
      end
    end
  end
end
