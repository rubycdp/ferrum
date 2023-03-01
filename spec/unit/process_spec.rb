# frozen_string_literal: true

describe Ferrum::Browser::Process do
  subject { Ferrum::Browser.new(port: 6000, host: "127.0.0.1") }

  unless Ferrum::Utils::Platform.windows?
    it "forcibly kills the child if it does not respond to SIGTERM" do
      allow(Process).to receive(:spawn).and_return(5678)
      allow(Process).to receive(:wait).and_return(nil)
      allow(Ferrum::Browser::Client).to receive(:new).and_return(double.as_null_object)

      allow_any_instance_of(Ferrum::Browser::Process).to receive(:parse_ws_url)

      subject.send(:start)

      expect(Process).to receive(:kill).with("USR1", 5678).ordered
      expect(Process).to receive(:kill).with("KILL", 5678).ordered

      subject.quit
    end
  end

  context "env variables" do
    subject { Ferrum::Browser.new(env: { "LD_PRELOAD" => "some.so" }) }

    it "passes through env" do
      allow(Process).to receive(:wait).and_return(nil)
      allow(Ferrum::Browser::Client).to receive(:new).and_return(double.as_null_object)

      allow(Process).to receive(:spawn).with({ "LD_PRELOAD" => "some.so" }, any_args).and_return(123_456_789)

      allow_any_instance_of(Ferrum::Browser::Process).to receive(:parse_ws_url)

      subject.send(:start)
      subject.quit
    end
  end
end
