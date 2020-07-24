# frozen_string_literal: true

require "image_size"
require "pdf/reader"
require "chunky_png"

module Ferrum
  describe Browser do
    context "screenshot support" do
      shared_examples "screenshot screen" do
        it "supports screenshotting the whole of a page that goes outside the viewport" do
          browser.goto("/ferrum/long_page")

          create_screenshot(path: file)

          File.open(file, "rb") do |f|
            expect(ImageSize.new(f.read).size).to eq(browser.viewport_size)
          end

          create_screenshot(path: file, full: true)

          File.open(file, "rb") do |f|
            expect(ImageSize.new(f.read).size).to eq(
              browser.evaluate("[document.documentElement.clientWidth, document.documentElement.clientHeight]")
            )
          end
        end

        it "supports screenshotting the entire window when documentElement has no height" do
          browser.goto("/ferrum/fixed_positioning")

          create_screenshot(path: file, full: true)

          File.open(file, "rb") do |f|
            expect(ImageSize.new(f.read).size).to eq(browser.viewport_size)
          end
        end

        it "supports screenshotting just the selected element" do
          browser.goto("/ferrum/long_page")

          create_screenshot(path: file, selector: "#penultimate")

          File.open(file, "rb") do |f|
            size = browser.evaluate <<-JS
              function() {
                var ele  = document.getElementById("penultimate");
                var rect = ele.getBoundingClientRect();
                return [rect.width, rect.height];
              }();
            JS
            expect(ImageSize.new(f.read).size).to eq(size)
          end
        end

        it "ignores :selector in #save_screenshot if full: true" do
          browser.goto("/ferrum/long_page")
          expect(browser.page).to receive(:warn).with(/Ignoring :selector/)

          create_screenshot(path: file, full: true, selector: "#penultimate")

          File.open(file, "rb") do |f|
            expect(ImageSize.new(f.read).size).to eq(
              browser.evaluate("[document.documentElement.clientWidth, document.documentElement.clientHeight]")
            )
          end
        end

        it "resets element positions after" do
          browser.goto("ferrum/long_page")
          el = browser.at_css("#middleish")
          # make the page scroll an element into view
          el.click
          position_script = "document.querySelector('#middleish').getBoundingClientRect()"
          offset = browser.evaluate(position_script)
          browser.screenshot(path: file)
          expect(browser.evaluate(position_script)).to eq offset
        end
      end

      describe "#screenshot" do
        let(:format) { :png }
        let(:file) { "#{PROJECT_ROOT}/spec/tmp/screenshot.#{format}" }

        def create_screenshot(**options)
          browser.screenshot(**options)
        end

        after do
          FileUtils.rm_f("#{PROJECT_ROOT}/spec/tmp/screenshot.pdf")
          FileUtils.rm_f("#{PROJECT_ROOT}/spec/tmp/screenshot.png")
        end

        it "supports screenshotting the page" do
          browser.goto

          browser.screenshot(path: file)

          expect(File.exist?(file)).to be true
        end

        it "supports screenshotting the page with a nonstring path" do
          browser.goto

          browser.screenshot(path: Pathname(file))

          expect(File.exist?(file)).to be true
        end

        context "fullscreen" do
          it "supports screenshotting of fullscreen" do
            browser.goto("/ferrum/custom_html_size")
            expect(browser.viewport_size).to eq([1024, 768])

            browser.screenshot(path: file, full: true)

            File.open(file, "rb") do |f|
              expect(ImageSize.new(f.read).size).to eq([1280, 1024])
            end
            expect(browser.viewport_size).to eq([1024, 768])
          end

          it "keeps current viewport" do
            browser.goto
            browser.resize(width: 800, height: 200)

            browser.screenshot(path: file, full: true)

            expect(File.exist?(file)).to be(true)
            expect(browser.viewport_size).to eq([800, 200])
          end

          it "resets to previous viewport when exception is raised" do
            browser.goto("/ferrum/custom_html_size")
            browser.resize(width: 100, height: 100)

            allow(browser.page).to receive(:command).and_call_original
            expect(browser.page).to receive(:command)
              .with("Page.captureScreenshot", format: "png", clip: {
                x: 0, y: 0, width: 1280, height: 1024, scale: 1.0
              }).and_raise(StandardError)
            expect { browser.screenshot(path: file, full: true) }
              .to raise_exception(StandardError)

            expect(File.exist?(file)).not_to be
            expect(browser.viewport_size).to eq([100, 100])
          end
        end

        it "supports screenshotting the page to file without extension when format is specified" do
          begin
            file = PROJECT_ROOT + "/spec/tmp/screenshot"
            browser.goto

            browser.screenshot(path: file, format: "jpg")

            expect(File.exist?(file)).to be true
          ensure
            FileUtils.rm_f(file)
          end
        end

        it "supports screenshotting the page with different quality settings" do
          file2 = PROJECT_ROOT + "/spec/tmp/screenshot2.jpeg"
          file3 = PROJECT_ROOT + "/spec/tmp/screenshot3.jpeg"
          FileUtils.rm_f([file2, file3])

          begin
            browser.goto
            browser.screenshot(path: file, quality: 0) # ignored for png
            browser.screenshot(path: file2) # defaults to a quality of 75
            browser.screenshot(path: file3, quality: 100)
            expect(File.size(file)).to be > File.size(file2) # png by defult is bigger
            expect(File.size(file2)).to be < File.size(file3)
          ensure
            FileUtils.rm_f([file2, file3])
          end
        end

        shared_examples "when scale is set" do
          it "changes image dimensions" do
            browser.goto("/ferrum/zoom_test")

            black_pixels_count = lambda { |file|
              img = ChunkyPNG::Image.from_file(file)
              img.pixels.inject(0) { |i, p| p > 255 ? i + 1 : i }
            }

            browser.screenshot(path: file)
            before = black_pixels_count[file]

            browser.screenshot(path: file, scale: scale)
            after = black_pixels_count[file]

            expect(after.to_f / before.to_f).to eq(scale**2)
          end
        end

        context "zoom in" do
          let(:scale) { 2 }
          include_examples "when scale is set"
        end

        context "zoom out" do
          let(:scale) { 0.5 }
          include_examples "when scale is set"
        end

        context "when :paper_width and :paper_height are set" do
          it "changes pdf size" do
            browser.goto("/ferrum/long_page")

            browser.pdf(path: file, paper_width: 1.0, paper_height: 1.0)

            reader = PDF::Reader.new(file)
            reader.pages.each do |page|
              bbox = page.attributes[:MediaBox]
              width = (bbox[2] - bbox[0]) / 72
              expect(width).to eq(1)
            end
          end
        end

        context "when format is passed" do
          it "changes pdf size to A0" do
            browser.goto("/ferrum/long_page")

            browser.pdf(path: file, format: :A0)

            reader = PDF::Reader.new(file)
            reader.pages.each do |page|
              bbox = page.attributes[:MediaBox]
              width = (bbox[2] - bbox[0]) / 72
              expect(width.round(2)).to eq(33.10)
            end
          end

          it "specifying format and paperWidth will cause exception" do
            browser.goto("/ferrum/long_page")

            expect {
              browser.pdf(path: file, format: :A0, paper_width: 1.0)
            }.to raise_error(ArgumentError)
          end

          it "convert case correct" do
            browser.goto("/ferrum/long_page")

            allow(browser.page).to receive(:command).with("Page.printToPDF", hash_including(
               displayHeaderFooter: false,
               ignoreInvalidPageRanges: false,
               landscape: false,
               marginBottom: 0.4,
               marginLeft: 0.4,
               marginRight: 0.4,
               marginTop: 0.4,
               pageRanges: "",
               paperHeight: 11,
               paperWidth: 8.5,
               path: file,
               preferCSSPageSize: false,
               printBackground: false,
               scale: 1,
            )) { { "stream" => "1" } }

            allow(browser.page).to receive(:command).with("IO.read", hash_including(
              handle: "1"
            )) { { "data" => "", "base64Encoded" => false, "eof" => true } }

            browser.pdf(path: file, landscape: false,
                                    display_header_footer: false,
                                    print_background: false,
                                    scale: 1,
                                    paper_width: 8.5,
                                    paper_height: 11,
                                    margin_top: 0.4,
                                    margin_bottom: 0.4,
                                    margin_left: 0.4,
                                    margin_right: 0.4,
                                    page_ranges: "",
                                    ignore_invalid_page_ranges: false,
                                    prefer_css_page_size: false)
          end
        end

        include_examples "screenshot screen"

        context "when encoding is base64" do
          let(:file) { "#{PROJECT_ROOT}/spec/tmp/screenshot.#{format}" }

          def create_screenshot(path: file, **options)
            image = browser.screenshot(format: format, encoding: :base64, **options)
            File.open(file, "wb") { |f| f.write Base64.decode64(image) }
          end

          it "defaults to base64 when path isn't set" do
            browser.goto

            screenshot = browser.screenshot(format: format)

            expect(screenshot.length).to be > 100
          end

          it "supports screenshotting the page in base64" do
            browser.goto

            screenshot = browser.screenshot(encoding: :base64)

            expect(screenshot.length).to be > 100
          end

          context "png" do
            let(:format) { :png }
            after { FileUtils.rm_f(file) }

            include_examples "screenshot screen"
          end

          context "jpeg" do
            let(:format) { :jpeg }
            after { FileUtils.rm_f(file) }

            include_examples "screenshot screen"
          end
        end
      end
    end
  end
end
