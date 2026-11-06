# frozen_string_literal: true

describe Ferrum::Browser::Process do
  subject { Ferrum::Browser.new(port: 6000, host: "127.0.0.1") }

  let(:client) { double.as_null_object.tap { |client| allow(client).to receive(:command).and_return(client) } }

  describe "#stop", skip: Ferrum::Utils::Platform.windows? do
    it "kills the child forcibly if it does not respond to SIGTERM" do
      allow(Process).to receive(:spawn).and_return(5678)
      allow(Process).to receive(:wait).and_return(nil)
      allow(Ferrum::Client).to receive(:new).and_return(client)

      allow_any_instance_of(Ferrum::Browser::Process).to receive(:parse_ws_url)

      subject

      expect(Process).to receive(:kill).with("TERM", -5678).ordered
      expect(Process).to receive(:kill).with("KILL", -5678).ordered

      subject.quit
    end

    it "falls back to signaling the leader pid when the group can't be signaled" do
      allow(Process).to receive(:spawn).and_return(5678)
      allow(Process).to receive(:wait).and_return(nil)
      allow(Ferrum::Client).to receive(:new).and_return(client)

      allow_any_instance_of(Ferrum::Browser::Process).to receive(:parse_ws_url)

      subject

      allow(Process).to receive(:kill).with("TERM", -5678).and_raise(Errno::EPERM)
      expect(Process).to receive(:kill).with("TERM", 5678).ordered
      allow(Process).to receive(:kill).with("KILL", -5678).and_raise(Errno::EPERM)
      expect(Process).to receive(:kill).with("KILL", 5678).ordered

      subject.quit
    end

    it "falls back to signaling the pid directly when it isn't a process group leader" do
      # e.g. Xvfb, which is spawned without `pgroup: true`
      allow(Process).to receive(:spawn).and_return(5678)
      allow(Process).to receive(:wait).and_return(nil)
      allow(Ferrum::Client).to receive(:new).and_return(client)

      allow_any_instance_of(Ferrum::Browser::Process).to receive(:parse_ws_url)

      subject

      allow(Process).to receive(:kill).with("TERM", -5678).and_raise(Errno::ESRCH)
      expect(Process).to receive(:kill).with("TERM", 5678).ordered
      allow(Process).to receive(:kill).with("KILL", -5678).and_raise(Errno::ESRCH)
      expect(Process).to receive(:kill).with("KILL", 5678).ordered

      subject.quit
    end
  end

  describe "#start" do
    it "uses the requested :host instead of the address Chrome reports" do
      process = described_class.new(Ferrum::Browser::Options.new(host: "ferrum.localhost", port: 6001))
      allow(Process).to receive(:spawn) do |*, options|
        options[:out].write("DevTools listening on ws://127.0.0.1:6001/devtools/browser/" \
                            "11111111-1111-1111-1111-111111111111\n")
        5678
      end
      allow(Process).to receive(:wait).and_return(nil)
      allow(Process).to receive(:kill)

      process.start

      expect(process.host).to eq("ferrum.localhost")
      expect(process.port).to eq(6001)
      expect(process.ws_url.host).to eq("ferrum.localhost")
    ensure
      process.stop
    end

    it "keeps Chromium temporary files inside the browser user data directory", if: Ferrum::Utils::Platform.platform_name == :linux do
      process = described_class.new(Ferrum::Browser::Options.new)
      user_data_dir = process.instance_variable_get(:@user_data_dir)
      temp_dir = File.join(user_data_dir, "tmp")

      expect(Dir.exist?(temp_dir)).to be true
      expect(Process).to receive(:spawn) do |env, *|
        expect(env["TMPDIR"]).to eq(temp_dir)
        expect(env["LD_PRELOAD"]).to be_nil
        5678
      end
      allow(Ferrum::Browser::Process::Killer).to receive(:kill)
      allow_any_instance_of(described_class).to receive(:parse_ws_url)

      process.start
      process.stop

      expect(Dir.exist?(user_data_dir)).to be false
    ensure
      process&.stop
    end

    it "passes env through to the browser process" do
      allow(Process).to receive(:wait).and_return(nil)
      allow(Ferrum::Client).to receive(:new).and_return(client)

      allow(Process).to receive(:spawn).with(hash_including("LD_PRELOAD" => "some.so"), any_args).and_return(123_456_789)

      allow_any_instance_of(Ferrum::Browser::Process).to receive(:parse_ws_url)

      browser = Ferrum::Browser.new(env: { "LD_PRELOAD" => "some.so" })
      browser.quit
    end
  end
end
