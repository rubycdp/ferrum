# frozen_string_literal: true

require "spec_helper"

module Ferrum
  describe Browser do
    context "frame support" do
      it "supports selection by index" do
        browser.goto("/ferrum/frames")
        frame = browser.at_xpath("//iframe")

        browser.within_frame(frame) do
          expect(browser.frame_url).to end_with("/ferrum/slow")
        end
      end

      it "supports selection by element" do
        browser.goto("/ferrum/frames")
        frame = browser.at_css("iframe[name]")

        browser.within_frame(frame) do
          expect(browser.frame_url).to end_with("/ferrum/slow")
        end
      end

      it "supports selection by element without name or id" do
        browser.goto("/ferrum/frames")
        frame = browser.at_css("iframe:not([name]):not([id])")

        browser.within_frame(frame) do
          expect(browser.frame_url).to end_with("/ferrum/headers")
        end
      end

      it "supports selection by element with id but no name" do
        browser.goto("/ferrum/frames")
        frame = browser.at_css("iframe[id]:not([name])")

        browser.within_frame(frame) do
          expect(browser.frame_url).to end_with("/ferrum/get_cookie")
        end
      end

      it "waits for the frame to load" do
        browser.goto
        browser.execute <<-JS
          document.body.innerHTML += "<iframe src='/ferrum/slow' name='frame'>"
        JS
        frame = browser.at_xpath("//iframe[@name='frame']")

        browser.within_frame(frame) do
          expect(browser.frame_url).to end_with("/ferrum/slow")
          expect(browser.body).to include("slow page")
        end
        expect(URI.parse(browser.frame_url).path).to eq("/")
      end

      it "waits for the cross-domain frame to load" do
        browser.goto("/ferrum/frames")
        expect(browser.current_url).to eq(base_url("/ferrum/frames"))
        frame = browser.at_xpath("//iframe[@name='frame']")

        browser.within_frame(frame) do
          expect(browser.frame_url).to end_with("/ferrum/slow")
          expect(browser.body).to include("slow page")
        end

        expect(browser.frame_url).to end_with("/ferrum/frames")
      end

      context "with src == about:blank" do
        it "doesn't hang if no document created" do
          browser.goto
          browser.execute <<-JS
            document.body.innerHTML += "<iframe src='about:blank' name='frame'>"
          JS
          frame = browser.at_xpath("//iframe[@name='frame']")
          browser.within_frame(frame) do
            expect(browser.body).to eq("<html><head></head><body></body></html>")
          end
        end

        it "doesn't hang if built by JS" do
          browser.goto
          browser.execute <<-JS
            document.body.innerHTML += "<iframe src='about:blank' name='frame'>";
            var iframeDocument = document.querySelector("iframe[name='frame']").contentWindow.document;
            var content = "<html><body><p>Hello Frame</p></body></html>";
            iframeDocument.open("text/html", "replace");
            iframeDocument.write(content);
            iframeDocument.close();
          JS
          frame = browser.at_xpath("//iframe[@name='frame']")

          browser.within_frame(frame) do
            expect(browser.body).to include("Hello Frame")
          end
        end
      end

      context "with no src attribute" do
        it "doesn't hang if the srcdoc attribute is used" do
          browser.goto
          browser.execute <<-JS
            document.body.innerHTML += "<iframe srcdoc='<p>Hello Frame</p>' name='frame'>"
          JS
          frame = browser.at_xpath("//iframe[@name='frame']")

          browser.within_frame(frame) do
            expect(browser.body).to include("Hello Frame")
          end
        end

        it "doesn't hang if the frame is filled by JS" do
          browser.goto
          browser.execute <<-JS
            document.body.innerHTML += "<iframe id='frame' name='frame'>"
          JS
          browser.execute <<-JS
            var iframeDocument = document.querySelector("#frame").contentWindow.document;
            var content = "<html><body><p>Hello Frame</p></body></html>";
            iframeDocument.open("text/html", "replace");
            iframeDocument.write(content);
            iframeDocument.close();
          JS
          frame = browser.at_xpath("//iframe[@name='frame']")

          browser.within_frame(frame) do
            expect(browser.body).to include("Hello Frame")
          end
        end
      end

      it "supports clicking in a frame", skip: true do
        browser.goto
        browser.execute <<-JS
          document.body.innerHTML += "<iframe src='/ferrum/click_test' name='frame'>"
        JS
        sleep 0.5
        frame = browser.at_xpath("//iframe[@name = 'frame']")

        browser.within_frame(frame) do
          log = browser.at_css("#log")
          browser.at_css("#one").click
          expect(log.text).to eq("one")
        end
      end

      it "supports clicking in a frame with padding", skip: true do
        browser.goto
        browser.execute <<-JS
          document.body.innerHTML += "<iframe src='/ferrum/click_test' name='padded_frame' style='padding:100px;'>"
        JS
        frame = browser.at_xpath("//iframe[@name = 'padded_frame']")

        browser.within_frame(frame) do
          log = browser.at_css("#log")
          browser.at_css("#one").click
          expect(log.text).to eq("one")
        end
      end

      it "supports clicking in a frame nested in a frame", skip: true do
        browser.goto

        # The padding on the frame here is to differ the sizes of the two
        # frames, ensuring that their offsets are being calculated seperately.
        # This avoids a false positive where the same frame"s offset is
        # calculated twice, but the click still works because both frames had
        # the same offset.
        browser.execute <<-JS
          document.body.innerHTML += "<iframe src='/ferrum/nested_frame_test' name='outer_frame' style='padding:200px'>"
        JS

        browser.within_frame "outer_frame" do
          browser.within_frame "inner_frame" do
            log = browser.at_css("#log")
            browser.at_css("#one").click
            expect(log.text).to eq("one")
          end
        end
      end

      it "does not wait forever for the frame to load" do
        browser.goto

        expect do
          browser.within_frame("omg") {}
        end.to(raise_error do |e|
          # expect(e).to be_a(Capybara::ElementNotFound)
        end)
      end

      it "can get the frames url" do
        browser.goto("/ferrum/frames")

        frame = browser.at_xpath("//iframe")
        browser.within_frame(frame) do
          expect(browser.frame_url).to end_with("/ferrum/slow")
          expect(browser.current_url).to end_with("/ferrum/frames")
        end

        expect(browser.frame_url).to end_with("/ferrum/frames")
        expect(browser.current_url).to end_with("/ferrum/frames")
      end
    end
  end
end
