# frozen_string_literal: true

describe Ferrum::Browser::Xvfb, :launch, skip: !Ferrum::Browser::Binary.find("Xvfb") do
  let(:process) { xvfb_browser.process }
  let(:xvfb_browser) { Ferrum::Browser.new(default_options.merge(options)) }
  let(:default_options) { Hash(headless: true, xvfb: true) }

  describe ".start" do
    context "when headless with window_size" do
      let(:options) { Hash(window_size: [1400, 1400]) }

      it "runs the browser in Xvfb" do
        xvfb_browser.go_to(base_url)

        expect(xvfb_browser.body).to include("Hello world!")
        expect(process_alive?(process.xvfb.pid)).to be(true)
        expect(process.xvfb.screen_size).to eq("1400x1400x24")
        expect(process.xvfb.to_env).to eq("DISPLAY" => ":#{process.xvfb.display_id}")
      ensure
        xvfb_browser&.quit
        expect(process_alive?(process.xvfb.pid)).to be(false)
      end
    end

    context "when headless without window_size" do
      let(:options) { {} }

      it "runs the browser in Xvfb" do
        xvfb_browser.go_to(base_url)

        expect(xvfb_browser.body).to include("Hello world!")
        expect(process_alive?(process.xvfb.pid)).to be(true)
        expect(process.xvfb.screen_size).to eq("1024x768x24")
        expect(process.xvfb.to_env).to eq("DISPLAY" => ":#{process.xvfb.display_id}")
      ensure
        xvfb_browser&.quit
        expect(process_alive?(process.xvfb.pid)).to be(false)
      end
    end

    context "when headful" do
      let(:options) { Hash(headless: false) }

      it "runs the browser in Xvfb" do
        xvfb_browser.go_to(base_url)

        expect(xvfb_browser.body).to include("Hello world!")
        expect(process_alive?(process.xvfb.pid)).to be(true)
        expect(process.xvfb.screen_size).to eq("1024x768x24")
      ensure
        xvfb_browser&.quit
        pid = process&.xvfb&.pid
        expect(process_alive?(pid)).to be(false) if pid
      end
    end

    it "waits for an Xvfb that is slow to start before launching a headful browser" do
      Dir.mktmpdir do |dir|
        slow_xvfb = File.join(dir, "Xvfb")
        File.write(slow_xvfb, "#!/bin/sh\nsleep 1\nexec #{Ferrum::Browser::Binary.find('Xvfb')} \"$@\"\n", perm: 0o755)
        allow(Ferrum::Browser::Binary).to receive(:find).and_call_original
        allow(Ferrum::Browser::Binary).to receive(:find).with("Xvfb").and_return(slow_xvfb)

        browser = Ferrum::Browser.new(xvfb: true, headless: false)
        browser.go_to(base_url)

        expect(browser.body).to include("Hello world!")
      ensure
        browser&.quit
      end
    end
  end

  def process_alive?(pid)
    return false unless pid

    Process.kill(0, pid) == 1
  rescue Errno::ESRCH
    false
  end
end
