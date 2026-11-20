# frozen_string_literal: true

describe Ferrum::Downloads do
  let(:filename) { "attachment.pdf" }
  let(:save_path) { "/tmp/ferrum-downloads" }

  describe "#files" do
    it "saves an attachment" do
      page.downloads.set_behavior(save_path: save_path)
      page.await_download { page.go_to("/#{filename}") }

      expect(page.downloads.files.size).to eq(1)
      expect(page.downloads.files[0]).to include("frameId" => anything,
                                                 "guid" => anything,
                                                 "suggestedFilename" => "attachment.pdf",
                                                 "totalBytes" => 4911,
                                                 "url" => anything)
    ensure
      FileUtils.rm_rf(save_path)
    end
  end

  describe "#await_download" do
    it "returns the download the block starts" do
      page.downloads.set_behavior(save_path: save_path)

      download = page.await_download { page.go_to("/#{filename}") }

      expect(download).to include("suggestedFilename" => filename, "state" => "completed")
      expect(File.exist?("#{save_path}/#{filename}")).to be true
    ensure
      FileUtils.rm_rf(save_path)
    end

    it "returns nil when no download finishes in time" do
      page.downloads.set_behavior(save_path: save_path)
      start = Concurrent.monotonic_time

      expect(page.downloads.await_download(timeout: 1) { page.go_to("/attachment") }).to be_nil
      expect(Ferrum::Utils::ElapsedTime.elapsed_time(start)).to be > 1
      expect(File.exist?("#{save_path}/#{filename}")).to be false
    end

    it "raises without a block" do
      expect { page.await_download }.to raise_error(ArgumentError, /needs a block/)
    end
  end

  describe "#await_download!" do
    it "returns the download the block starts" do
      page.downloads.set_behavior(save_path: save_path)

      expect(page.await_download! { page.go_to("/#{filename}") }).to include("state" => "completed")
    ensure
      FileUtils.rm_rf(save_path)
    end

    it "raises when the download doesn't finish in time" do
      page.downloads.set_behavior(save_path: save_path)

      expect { page.await_download!(timeout: 0.5) { page.go_to("/attachment") } }.to raise_error(Ferrum::TimeoutError)
    end
  end

  describe "#wait" do
    it "waits for the download the block starts and warns that it is deprecated" do
      page.downloads.set_behavior(save_path: save_path)
      Ferrum::Utils::Deprecate.reset!

      expect { page.downloads.wait(2) { page.go_to("/#{filename}") } }
        .to output(/downloads\.wait will be removed in Ferrum 0\.22.*called from #{__FILE__}/m).to_stderr
      expect(File.exist?("#{save_path}/#{filename}")).to be true
    ensure
      FileUtils.rm_rf(save_path)
    end
  end

  describe "#set_behavior" do
    context "with absolute path" do
      it "saves an attachment" do
        page.downloads.set_behavior(save_path: save_path)
        page.await_download { page.go_to("/#{filename}") }

        expect(File.exist?("#{save_path}/#{filename}")).to be true
      ensure
        FileUtils.rm_rf(save_path)
      end

      it "saves no attachment when behavior is deny" do
        page.downloads.set_behavior(save_path: save_path, behavior: :deny)
        page.await_download(timeout: 1) { page.go_to("/#{filename}") }

        expect(File.exist?("#{save_path}/#{filename}")).to be false
      end

      it "saves an attachment on click" do
        page.downloads.set_behavior(save_path: save_path)
        page.go_to("/attachment")
        page.await_download { page.at_css("#download").click }

        expect(File.exist?("#{save_path}/#{filename}")).to be true
      ensure
        FileUtils.rm_rf(save_path)
      end
    end

    context "with the browser's implicit context" do
      it "saves an attachment", :launch do
        with_external_browser(incognito: false) do |url|
          remote = Ferrum::Browser.new(url: url, base_url: base_url, save_path: save_path)
          remote_page = remote.create_page

          expect(remote_page.context_id).to be_nil

          remote_page.await_download { remote_page.go_to("/#{filename}") }

          expect(File.exist?("#{save_path}/#{filename}")).to be true
        ensure
          remote&.quit
          FileUtils.rm_rf(save_path)
        end
      end
    end

    context "with local path" do
      let(:save_path) { "spec/tmp" }

      it "raises an error" do
        expect do
          page.downloads.set_behavior(save_path: save_path)
        end.to raise_error(Ferrum::Error, "supply absolute path for `:save_path` option")

        page.go_to("/#{filename}")
        expect(File.exist?("#{save_path}/#{filename}")).to be false
      end
    end
  end
end
