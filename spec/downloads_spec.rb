# frozen_string_literal: true

describe Ferrum::Downloads do
  let(:filename) { "attachment.pdf" }
  let(:save_path) { "/tmp/ferrum" }

  def skip_browser_bug
    # Also https://github.com/puppeteer/puppeteer/issues/10161
    skip "https://bugs.chromium.org/p/chromium/issues/detail?id=1444729"
  end

  describe "#files" do
    it "saves an attachment" do
      skip_browser_bug

      page.downloads.set_behavior(save_path: save_path)
      page.go_to("/#{filename}")
      page.downloads.wait

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

  describe "#wait" do
    it "times out" do
      page.downloads.set_behavior(save_path: save_path)
      page.go_to("/attachment")
      start = Concurrent.monotonic_time
      page.downloads.wait(2)

      expect(Ferrum::Utils::ElapsedTime.elapsed_time(start)).to be > 2
      expect(File.exist?("#{save_path}/#{filename}")).to be false
    end

    it "accepts block" do
      page.downloads.set_behavior(save_path: save_path)
      page.downloads.wait(2) { page.go_to("/attachment") }

      expect(File.exist?("#{save_path}/#{filename}")).to be false
    end
  end

  describe "#set_behavior" do
    context "with absolute path" do
      it "saves an attachment" do
        skip_browser_bug

        page.downloads.set_behavior(save_path: save_path)
        page.go_to("/#{filename}")
        page.downloads.wait

        expect(File.exist?("#{save_path}/#{filename}")).to be true
      ensure
        FileUtils.rm_rf(save_path)
      end

      it "saves no attachment when behavior is deny" do
        skip_browser_bug

        page.downloads.set_behavior(save_path: save_path, behavior: :deny)
        page.downloads.wait { page.go_to("/#{filename}") }

        expect(File.exist?("#{save_path}/#{filename}")).to be false
      end

      it "saves an attachment on click" do
        skip_browser_bug

        page.downloads.set_behavior(save_path: save_path)
        page.go_to("/attachment")
        page.downloads.wait { page.at_css("#download").click }

        expect(File.exist?("#{save_path}/#{filename}")).to be true
      ensure
        FileUtils.rm_rf(save_path)
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
