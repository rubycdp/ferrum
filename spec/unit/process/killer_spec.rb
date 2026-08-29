# frozen_string_literal: true

require "tmpdir"

describe Ferrum::Browser::Process::Killer do
  describe ".remove_directory" do
    it "removes an existing directory" do
      dir = Dir.mktmpdir

      described_class.remove_directory(dir)

      expect(Dir.exist?(dir)).to be false
    end

    it "treats an already-gone directory as success, without warning" do
      dir = Dir.mktmpdir
      FileUtils.remove_entry(dir)

      expect(described_class).not_to receive(:warn)
      expect { described_class.remove_directory(dir) }.not_to raise_error
    end

    it "retries a transient error and succeeds once it clears" do
      dir = Dir.mktmpdir
      attempts = 0
      allow(FileUtils).to receive(:remove_entry).and_wrap_original do |original, path|
        attempts += 1
        raise Errno::ENOTEMPTY, path if attempts == 1

        original.call(path)
      end

      described_class.remove_directory(dir, retries: 3, delay: 0.001)

      expect(attempts).to eq(2)
      expect(Dir.exist?(dir)).to be false
    end

    it "warns and gives up without raising once retries are exhausted" do
      dir = Dir.mktmpdir
      allow(FileUtils).to receive(:remove_entry).and_raise(Errno::EBUSY)

      expect(described_class).to receive(:warn).with(a_string_matching(/Errno::EBUSY/))
      expect { described_class.remove_directory(dir, retries: 2, delay: 0.001) }.not_to raise_error
    ensure
      Dir.rmdir(dir)
    end

    it "warns instead of raising on an error it doesn't specifically retry" do
      dir = Dir.mktmpdir
      allow(FileUtils).to receive(:remove_entry).and_raise(ArgumentError, "boom")

      expect(described_class).to receive(:warn).with(a_string_matching(/ArgumentError: boom/))
      expect { described_class.remove_directory(dir) }.not_to raise_error
    ensure
      Dir.rmdir(dir)
    end
  end

  describe ".wait_reaped", if: Ferrum::Utils::Platform.mri? && !Ferrum::Utils::Platform.windows? do
    it "returns the pid once the process has exited" do
      pid = Process.spawn("true")

      expect(described_class.wait_reaped(pid)).to eq(pid)
    end

    it "returns nil for a process that was never ours" do
      expect(described_class.wait_reaped(1, timeout: 0.1)).to be_nil
    end

    # #kill is installed as an ObjectSpace finalizer, so it can run while the
    # interpreter is shutting down. A blocking Process.wait there never
    # returns and the process hangs instead of exiting -- cuprite#231.
    it "gives up rather than blocking forever on a process that won't exit" do
      pid = Process.spawn("sleep 30")
      start = Ferrum::Utils::ElapsedTime.monotonic_time

      expect(described_class.wait_reaped(pid, timeout: 0.2)).to be_nil
      expect(Ferrum::Utils::ElapsedTime.monotonic_time - start).to be < 5
    ensure
      Process.kill("KILL", pid)
      Process.wait(pid)
    end
  end

  describe ".finalizer", if: Ferrum::Utils::Platform.mri? && !Ferrum::Utils::Platform.windows? do
    def reaped?(pid)
      Process.waitpid(pid, Process::WNOHANG)
      false
    rescue Errno::ECHILD
      true
    end

    it "kills the process before removing its directory" do
      dir = Dir.mktmpdir
      # Stands in for Chrome, which writes to its profile on the way out: a
      # directory removed while it is still alive comes straight back.
      pid = Process.spawn(RbConfig.ruby, "-e", <<~RUBY, dir, pgroup: true)
        require "fileutils"
        trap("TERM") do
          FileUtils.mkdir_p(ARGV[0])
          File.write(File.join(ARGV[0], "lock"), "x")
          exit!
        end
        FileUtils.mkdir_p(ARGV[0])
        File.write(File.join(ARGV[0], "lock"), "x")
        loop { sleep 0.05 }
      RUBY
      start = Ferrum::Utils::ElapsedTime.monotonic_time
      sleep(0.02) until File.exist?(File.join(dir, "lock")) ||
                        Ferrum::Utils::ElapsedTime.timeout?(start, 5)

      described_class.finalizer(pid, dir).call
      sleep(0.2)

      expect(Dir.exist?(dir)).to be false
    ensure
      begin
        Process.kill("KILL", pid) if pid
      rescue Errno::ESRCH
        nil
      end
      FileUtils.remove_entry(dir) if Dir.exist?(dir.to_s)
    end

    it "kills every pid it was given" do
      pids = Array.new(2) { Process.spawn("sleep 30", pgroup: true) }

      described_class.finalizer(pids, nil).call

      expect(pids.map { |pid| reaped?(pid) }).to all(be true)
    end

    it "removes the directory when there is nothing to kill" do
      dir = Dir.mktmpdir

      described_class.finalizer(nil, dir).call

      expect(Dir.exist?(dir)).to be false
    end
  end

  describe ".process_group_alive?", if: Ferrum::Utils::Platform.mri? do
    it "returns true while the process group has a live member" do
      pid = Process.spawn("sleep 30", pgroup: true)

      begin
        expect(described_class.process_group_alive?(pid)).to be true
      ensure
        Process.kill("KILL", -pid)
        Process.wait(pid)
      end
    end

    it "returns false once the process group is gone" do
      pid = Process.spawn("true", pgroup: true)
      Process.wait(pid)

      expect(described_class.process_group_alive?(pid)).to be false
    end
  end
end
