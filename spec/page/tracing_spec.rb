# frozen_string_literal: true

describe Ferrum::Page::Tracing do
  let(:file_path) { "#{PROJECT_ROOT}/spec/tmp/trace.json" }
  let(:file_path2) { "#{PROJECT_ROOT}/spec/tmp/trace2.json" }
  let(:file_path3) { "#{PROJECT_ROOT}/spec/tmp/trace3.json" }
  let(:content) { JSON.parse(File.read(file_path)) }
  let(:trace_config) { JSON.parse(content["metadata"]["trace-config"]) }

  after do
    FileUtils.rm_f(file_path)
    FileUtils.rm_f(file_path2)
    FileUtils.rm_f(file_path3)
  end

  describe "#record" do
    it "outputs a trace to file" do
      page.tracing.record(path: file_path) { page.go_to }

      expect(File.exist?(file_path)).to be(true)
    end

    it "runs with custom options" do
      page.tracing.record(
        path: file_path,
        trace_config: {
          includedCategories: ["disabled-by-default-devtools.timeline"],
          excludedCategories: ["*"]
        }
      ) { page.go_to }

      expect(File.exist?(file_path)).to be(true)
      expect(trace_config["excluded_categories"]).to eq(["*"])
      expect(trace_config["included_categories"]).to eq(["disabled-by-default-devtools.timeline"])
      expect(content["traceEvents"].any? { |o| o["cat"] == "toplevel" }).to eq(false)
    end

    it "runs with default categories" do
      page.tracing.record(path: file_path) { page.go_to }

      expect(File.exist?(file_path)).to be(true)
      expect(trace_config["excluded_categories"]).to eq(["*"])
      expect(trace_config["included_categories"])
        .to match_array(%w[devtools.timeline v8.execute disabled-by-default-devtools.timeline
                           disabled-by-default-devtools.timeline.frame toplevel blink.console
                           blink.user_timing latencyInfo disabled-by-default-devtools.timeline.stack
                           disabled-by-default-v8.cpu_profiler disabled-by-default-v8.cpu_profiler.hires])
      expect(content["traceEvents"].any? { |o| o["cat"] == "toplevel" }).to eq(true)
    end

    it "raises an error when tracing is on two pages" do
      page.tracing.record(path: file_path) do
        page.go_to

        expect do
          another = browser.create_page
          another.tracing.record(path: file_path2) { another.go_to }
        end.to raise_exception(Ferrum::BrowserError, "Tracing has already been started (possibly in another tab).")
        expect(File.exist?(file_path2)).to be(false)
      end

      expect(File.exist?(file_path)).to be(true)
    end

    it "raises an error when cannot handle stream" do
      allow(page.tracing).to receive(:stream_handle).and_raise("boom")
      expect do
        page.tracing.record(path: file_path) { page.go_to }
      end.to raise_error(RuntimeError, "boom")

      expect(File.exist?(file_path)).to be(false)
    end

    it "handles tracing complete event once" do
      expect(page.tracing).to receive(:stream_handle).exactly(3).times.and_call_original

      page.tracing.record(path: file_path) { page.go_to }
      expect(File.exist?(file_path)).to be(true)

      page.tracing.record(path: file_path2) { page.go_to }
      expect(File.exist?(file_path2)).to be(true)

      page.tracing.record(path: file_path3) { page.go_to }
      expect(File.exist?(file_path3)).to be(true)
    end

    it "returns base64 encoded string" do
      trace = page.tracing.record(encoding: :base64) { page.go_to }

      decoded = Base64.decode64(trace)
      content = JSON.parse(decoded)
      expect(content["traceEvents"].any?).to eq(true)
    end

    it "returns buffer with no encoding" do
      trace = page.tracing.record { page.go_to }

      content = JSON.parse(trace)
      expect(content["traceEvents"].any?).to eq(true)
    end

    context "with screenshots enabled" do
      it "fills file with screenshot data" do
        page.tracing.record(path: file_path, screenshots: true) { page.go_to("/grid") }

        expect(File.exist?(file_path)).to be(true)
        expect(trace_config["included_categories"]).to include("disabled-by-default-devtools.screenshot")
        expect(content["traceEvents"].any? { |o| o["name"] == "Screenshot" }).to eq(true)
      end

      it "returns a buffer with screenshot data" do
        trace = page.tracing.record(screenshots: true) { page.go_to("/grid") }

        expect(File.exist?(file_path)).to be(false)
        content = JSON.parse(trace)
        trace_config = JSON.parse(content["metadata"]["trace-config"])
        expect(trace_config["included_categories"]).to include("disabled-by-default-devtools.screenshot")
        expect(content["traceEvents"].any? { |o| o["name"] == "Screenshot" }).to eq(true)
      end
    end

    it "waits for promise fill with timeout when it provided" do
      expect(page.tracing).to receive(:subscribe_tracing_complete).with(no_args)
      trace = page.tracing.record(timeout: 1) { page.go_to }
      expect(trace).to be_nil
    end
  end
end
