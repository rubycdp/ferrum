# frozen_string_literal: true

module Ferrum
  describe Browser::Xvfb, skip: !Browser::Xvfb.xvfb_path do
    let(:process) { xvfb_browser.process }
    let(:xvfb_browser) { Browser.new(default_options.merge(options)) }
    let(:default_options) { Hash(headless: true, xvfb: true) }

    context "headless" do
      context "with window_size" do
        let(:options) { Hash(window_size: [1400, 1400]) }

        it "allows to run tests configured to xvfb" do
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

      context "without window_size" do
        let(:options) { {} }

        it "allows to run tests configured to xvfb" do
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
    end

    context "headful" do
      let(:options) { Hash(headless: false) }

      it "allows to run tests configured to xvfb" do
        xvfb_browser.go_to(base_url)

        expect(xvfb_browser.body).to include("Hello world!")
        expect(process_alive?(process.xvfb.pid)).to be(true)
        expect(process.xvfb.screen_size).to eq("1024x768x24")
      ensure
        xvfb_browser&.quit
        expect(process_alive?(process.xvfb.pid)).to be(false)
      end
    end

    def process_alive?(pid)
      return false unless pid

      ::Process.kill(0, pid) == 1
    rescue Errno::ESRCH
      false
    end
  end
end
