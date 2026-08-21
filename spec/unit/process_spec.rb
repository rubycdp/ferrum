# frozen_string_literal: true

describe Ferrum::Browser::Process do
  subject { Ferrum::Browser.new(port: 6000, host: "127.0.0.1") }

  unless Ferrum::Utils::Platform.windows?
    it "forcibly kills the child if it does not respond to SIGTERM" do
      allow(Process).to receive(:spawn).and_return(5678)
      allow(Process).to receive(:wait).and_return(nil)
      allow(Ferrum::Client).to receive(:new).and_return(double.as_null_object)

      allow_any_instance_of(Ferrum::Browser::Process).to receive(:parse_ws_url)
      allow_any_instance_of(Ferrum::Browser::Process).to receive(:parse_json_version)

      subject.send(:start)

      expect(Process).to receive(:kill).with("TERM", -5678).ordered
      expect(Process).to receive(:kill).with("KILL", -5678).ordered

      subject.quit
    end

    it "falls back to signaling the leader pid when the group can't be signaled" do
      allow(Process).to receive(:spawn).and_return(5678)
      allow(Process).to receive(:wait).and_return(nil)
      allow(Ferrum::Client).to receive(:new).and_return(double.as_null_object)

      allow_any_instance_of(Ferrum::Browser::Process).to receive(:parse_ws_url)
      allow_any_instance_of(Ferrum::Browser::Process).to receive(:parse_json_version)

      subject.send(:start)

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
      allow(Ferrum::Client).to receive(:new).and_return(double.as_null_object)

      allow_any_instance_of(Ferrum::Browser::Process).to receive(:parse_ws_url)
      allow_any_instance_of(Ferrum::Browser::Process).to receive(:parse_json_version)

      subject.send(:start)

      allow(Process).to receive(:kill).with("TERM", -5678).and_raise(Errno::ESRCH)
      expect(Process).to receive(:kill).with("TERM", 5678).ordered
      allow(Process).to receive(:kill).with("KILL", -5678).and_raise(Errno::ESRCH)
      expect(Process).to receive(:kill).with("KILL", 5678).ordered

      subject.quit
    end

    it "kills the whole process group, not just the leader, when a group member ignores TERM", if: Ferrum::Utils::Platform.mri? do
      child_pid_path = File.join(Dir.tmpdir, "ferrum-process-spec-child-pid-#{Process.pid}")

      script = <<~RUBY
        pid = fork do
          trap("TERM", "IGNORE")
          sleep 30
        end
        Process.detach(pid)
        File.write(#{child_pid_path.inspect}, pid.to_s)
        sleep 30
      RUBY
      leader_pid = Process.spawn(RbConfig.ruby, "-e", script, pgroup: true)

      begin
        start = Ferrum::Utils::ElapsedTime.monotonic_time
        sleep(0.05) until File.size?(child_pid_path) || Ferrum::Utils::ElapsedTime.timeout?(start, 5)
        child_pid = File.read(child_pid_path).to_i

        # A leader that dies promptly on TERM must not short-circuit the
        # escalation to KILL for the rest of its process group.
        Ferrum::Browser::Process::Killer.kill(leader_pid)
        sleep(0.2)

        expect { Process.kill(0, child_pid) }.to raise_error(Errno::ESRCH)
      ensure
        File.delete(child_pid_path) if child_pid && File.exist?(child_pid_path)
      end
    end
  end

  context "when spawning Chrome itself" do
    it "uses the requested :host instead of the address Chrome reports" do
      subject = described_class.new(Ferrum::Browser::Options.new(host: "ferrum.localhost", port: 6001))
      read_io, write_io = IO.pipe
      write_io.write("DevTools listening on ws://127.0.0.1:6001/devtools/browser/" \
                     "11111111-1111-1111-1111-111111111111\n")
      write_io.close

      subject.send(:parse_ws_url, read_io, 1)

      expect(subject.host).to eq("ferrum.localhost")
      expect(subject.port).to eq(6001)
      expect(subject.ws_url.host).to eq("ferrum.localhost")
    end
  end

  context "env variables" do
    subject { Ferrum::Browser.new(env: { "LD_PRELOAD" => "some.so" }) }

    it "passes through env" do
      allow(Process).to receive(:wait).and_return(nil)
      allow(Ferrum::Client).to receive(:new).and_return(double.as_null_object)

      allow(Process).to receive(:spawn).with({ "LD_PRELOAD" => "some.so" }, any_args).and_return(123_456_789)

      allow_any_instance_of(Ferrum::Browser::Process).to receive(:parse_ws_url)
      allow_any_instance_of(Ferrum::Browser::Process).to receive(:parse_json_version)

      subject.send(:start)
      subject.quit
    end
  end
end
