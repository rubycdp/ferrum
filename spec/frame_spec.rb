# frozen_string_literal: true

require "spec_helper"

module Ferrum
  describe Browser do
    context "frame support" do
      it "supports selection by index" do
        browser.goto("/ferrum/frames")
        frame = browser.at_xpath("//iframe").frame
        expect(frame.url).to end_with("/ferrum/slow")
      end

      it "supports selection by element" do
        browser.goto("/ferrum/frames")
        frame = browser.at_css("iframe[name]").frame
        expect(frame.url).to end_with("/ferrum/slow")
      end

      it "supports selection by element without name or id" do
        browser.goto("/ferrum/frames")
        frame = browser.at_css("iframe:not([name]):not([id])").frame
        expect(frame.url).to end_with("/ferrum/headers")
      end

      it "supports selection by element with id but no name" do
        browser.goto("/ferrum/frames")
        frame = browser.at_css("iframe[id]:not([name])").frame
        expect(frame.url).to end_with("/ferrum/get_cookie")
      end

      it "waits for the frame to load" do
        browser.goto
        browser.execute <<-JS
          document.body.innerHTML += "<iframe src='/ferrum/slow' name='frame'>"
        JS

        frame = browser.at_xpath("//iframe[@name='frame']").frame
        expect(frame.url).to end_with("/ferrum/slow")
        expect(frame.body).to include("slow page")

        expect(browser.main_frame.url).to end_with("/")
      end

      it "waits for the cross-domain frame to load" do
        browser.goto("/ferrum/frames")
        expect(browser.current_url).to eq(base_url("/ferrum/frames"))
        frame = browser.at_xpath("//iframe[@name='frame']").frame

        expect(frame.url).to end_with("/ferrum/slow")
        expect(frame.body).to include("slow page")

        expect(browser.current_url).to end_with("/ferrum/frames")
      end

      context "with src == about:blank" do
        it "doesn't hang if no document created" do
          browser.goto
          browser.execute <<-JS
            document.body.innerHTML += "<iframe src='about:blank' name='frame'>"
          JS
          frame = browser.at_xpath("//iframe[@name='frame']").frame
          expect(frame.body).to eq("<html><head></head><body></body></html>")
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
          frame = browser.at_xpath("//iframe[@name='frame']").frame
          expect(frame.body).to include("Hello Frame")
        end
      end

      context "with no src attribute" do
        it "doesn't hang if the srcdoc attribute is used" do
          browser.goto
          browser.execute <<-JS
            document.body.innerHTML += "<iframe srcdoc='<p>Hello Frame</p>' name='frame'>"
          JS
          frame = browser.at_xpath("//iframe[@name='frame']").frame
          expect(frame.body).to include("Hello Frame")
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
          frame = browser.at_xpath("//iframe[@name='frame']").frame
          expect(frame.body).to include("Hello Frame")
        end
      end

      context "#add_script_tag" do
        it "adds by url" do
          browser.goto
          expect {
            browser.evaluate("$('a').first().text()")
          }.to raise_error(Ferrum::JavaScriptError)

          browser.add_script_tag(url: "/ferrum/jquery.min.js")

          expect(browser.evaluate("$('a').first().text()")).to eq("Relative")
        end

        it "adds by path" do
          browser.goto
          path = "#{Ferrum::Application::FERRUM_PUBLIC}/jquery-1.11.3.min.js"
          expect {
            browser.evaluate("$('a').first().text()")
          }.to raise_error(Ferrum::JavaScriptError)

          browser.add_script_tag(path: path)

          expect(browser.evaluate("$('a').first().text()")).to eq("Relative")
        end

        it "adds by content" do
          browser.goto

          browser.add_script_tag(content: "function yay() { return 'yay!'; }")

          expect(browser.evaluate("yay()")).to eq("yay!")
        end
      end

      context "#add_style_tag" do
        let(:font_size) {
          <<~JS
            window
              .getComputedStyle(document.querySelector('a'))
              .getPropertyValue('font-size')
          JS
        }

        it "adds by url" do
          browser.goto
          expect(browser.evaluate(font_size)).to eq("16px")

          browser.add_style_tag(url: "/ferrum/add_style_tag.css")

          expect(browser.evaluate(font_size)).to eq("50px")
        end

        it "adds by path" do
          browser.goto
          path = "#{Ferrum::Application::FERRUM_PUBLIC}/add_style_tag.css"
          expect(browser.evaluate(font_size)).to eq("16px")

          browser.add_style_tag(path: path)

          expect(browser.evaluate(font_size)).to eq("50px")
        end

        it "adds by content" do
          browser.goto

          browser.add_style_tag(content: "a { font-size: 20px; }")

          expect(browser.evaluate(font_size)).to eq("20px")
        end
      end

      it "supports clicking in a frame", skip: true do
        browser.goto
        browser.execute <<-JS
          document.body.innerHTML += "<iframe src='/ferrum/click_test' name='frame'>"
        JS
        sleep 0.5
        frame = browser.at_xpath("//iframe[@name = 'frame']").frame

        log = frame.at_css("#log")
        frame.at_css("#one").click
        expect(log.text).to eq("one")
      end

      it "supports clicking in a frame with padding", skip: true do
        browser.goto
        browser.execute <<-JS
          document.body.innerHTML += "<iframe src='/ferrum/click_test' name='padded_frame' style='padding:100px;'>"
        JS
        frame = browser.at_xpath("//iframe[@name = 'padded_frame']").frame

        log = frame.at_css("#log")
        frame.at_css("#one").click
        expect(log.text).to eq("one")
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

        sleep 0.5

        inner_frame = browser.frame_by(name: "inner_frame")
        log = inner_frame.at_css("#log")
        inner_frame.at_css("#one").click
        expect(log.text).to eq("one")
      end

      it "does not wait forever for the frame to load" do
        browser.goto

        frame = browser.frame_by(name: "omg")

        expect(frame).to be_nil
      end

      it "can get the frames url" do
        browser.goto("/ferrum/frames")

        frame = browser.at_xpath("//iframe").frame
        expect(frame.url).to end_with("/ferrum/slow")
        expect(browser.current_url).to end_with("/ferrum/frames")
      end

      it "can set page content" do
        browser.set_content(%(<html><head></head><body>Voila!</body></html>))

        expect(browser.body).to include("Voila!")
      end
    end
  end
end
