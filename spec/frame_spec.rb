# frozen_string_literal: true

module Ferrum
  describe Frame do
    context "frame support" do
      it "supports selection by index" do
        browser.go_to("/ferrum/frames")
        frame = browser.at_xpath("//iframe").frame
        expect(frame.url).to end_with("/ferrum/slow")
      end

      it "supports selection by element" do
        browser.go_to("/ferrum/frames")
        frame = browser.at_css("iframe[name]").frame
        expect(frame.url).to end_with("/ferrum/slow")
      end

      it "supports selection by element without name or id" do
        browser.go_to("/ferrum/frames")
        frame = browser.at_css("iframe:not([name]):not([id])").frame
        expect(frame.url).to end_with("/ferrum/headers")
      end

      it "supports selection by element with id but no name" do
        browser.go_to("/ferrum/frames")
        frame = browser.at_css("iframe[id]:not([name])").frame
        expect(frame.url).to end_with("/ferrum/get_cookie")
      end

      it "finds main frame properly" do
        browser.go_to("/ferrum/popup_frames")

        browser.at_xpath("//a[text()='pop up']").click

        expect(browser.pages.size).to eq(2)
        opened_page = browser.pages.last
        expect(opened_page.main_frame.url).to end_with("/frames")
      end

      it "waits for the frame to load" do
        browser.go_to
        browser.execute <<-JS
          document.body.innerHTML += "<iframe src='/ferrum/slow' name='frame'>"
        JS

        frame = browser.at_xpath("//iframe[@name='frame']").frame
        expect(frame.url).to end_with("/ferrum/slow")
        expect(frame.body).to include("slow page")

        expect(browser.main_frame.url).to end_with("/")
      end

      it "waits for the cross-domain frame to load" do
        browser.go_to("/ferrum/frames")
        expect(browser.current_url).to eq(base_url("/ferrum/frames"))
        frame = browser.at_xpath("//iframe[@name='frame']").frame

        expect(frame.url).to end_with("/ferrum/slow")
        expect(frame.body).to include("slow page")

        expect(browser.current_url).to end_with("/ferrum/frames")
      end

      context "with src == about:blank" do
        it "doesn't hang if no document created" do
          browser.go_to
          browser.execute <<-JS
            document.body.innerHTML += "<iframe src='about:blank' name='frame'>"
          JS
          frame = browser.at_xpath("//iframe[@name='frame']").frame
          expect(frame.body).to eq("<html><head></head><body></body></html>")
        end

        it "doesn't hang if built by JS" do
          browser.go_to
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
          browser.go_to
          browser.execute <<-JS
            document.body.innerHTML += "<iframe srcdoc='<p>Hello Frame</p>' name='frame'>"
          JS
          frame = browser.at_xpath("//iframe[@name='frame']").frame
          expect(frame.body).to include("Hello Frame")
        end

        it "doesn't hang if the frame is filled by JS" do
          browser.go_to
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

      it "supports clicking in a frame", skip: true do
        browser.go_to
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
        browser.go_to
        browser.execute <<-JS
          document.body.innerHTML += "<iframe src='/ferrum/click_test' name='padded_frame' style='padding:100px;'>"
        JS
        frame = browser.at_xpath("//iframe[@name = 'padded_frame']").frame

        log = frame.at_css("#log")
        frame.at_css("#one").click
        expect(log.text).to eq("one")
      end

      it "supports clicking in a frame nested in a frame", skip: true do
        browser.go_to

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
        browser.go_to

        frame = browser.frame_by(name: "omg")

        expect(frame).to be_nil
      end

      it "can get the frames url" do
        browser.go_to("/ferrum/frames")

        frame = browser.at_xpath("//iframe").frame
        expect(frame.url).to end_with("/ferrum/slow")
        expect(browser.current_url).to end_with("/ferrum/frames")
      end

      it "can set page content" do
        browser.content = "<html><head></head><body>Voila!</body></html>"

        expect(browser.body).to include("Voila!")
      end

      it "gets page doctype" do
        browser.go_to("/ferrum/frames")
        expect(browser.doctype).to eq("<!DOCTYPE html>")

        doctype40 = %(<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">)
        browser.content = "#{doctype40}<html><head></head><body>Voila!</body></html>"
        expect(browser.doctype).to eq(doctype40)

        browser.content = ""
        expect(browser.doctype).to be_nil
      end

      context "#xpath" do
        it "returns given nodes" do
          browser.go_to("/ferrum/with_js")
          p = browser.xpath("//p[@id='remove_me']")

          expect(p.size).to eq(1)
        end

        it "supports within" do
          browser.go_to("/ferrum/with_js")
          p = browser.xpath("//p[@id='with_content']").first

          links = browser.xpath("./a", within: p)

          expect(links.size).to eq(1)
          expect(links.first.attribute(:id)).to eq("open-match")
        end

        it "throws an error on a wrong xpath" do
          browser.go_to("/ferrum/with_js")

          expect do
            browser.xpath("#remove_me")
          end.to raise_error(Ferrum::JavaScriptError)
        end

        it "supports inside a given frame" do
          browser.go_to("/ferrum/frames")
          browser.execute <<-JS
            document.body.innerHTML += "<iframe src='/ferrum/buttons' id='buttons_frame'>"
          JS
          browser.network.wait_for_idle

          frame = browser.at_xpath("//iframe[@id='buttons_frame']").frame
          expect(frame.xpath("//button").size).to eq(3)
        end
      end

      context "#at_xpath" do
        it "returns given nodes" do
          browser.go_to("/ferrum/with_js")
          p = browser.at_xpath("//p[@id='remove_me']")

          expect(p).not_to be_nil
        end

        it "supports within" do
          browser.go_to("/ferrum/with_js")
          p = browser.at_xpath("//p[@id='with_content']")

          link = browser.at_xpath("./a", within: p)

          expect(link).not_to be_nil
          expect(link.attribute(:id)).to eq("open-match")
        end

        it "throws an error on a wrong xpath" do
          browser.go_to("/ferrum/with_js")

          expect do
            browser.at_xpath("#remove_me")
          end.to raise_error(Ferrum::JavaScriptError)
        end

        it "supports inside a given frame" do
          browser.go_to("/ferrum/frames")
          browser.execute <<-JS
            document.body.innerHTML += "<iframe src='/ferrum/buttons' id='buttons_frame'>"
          JS
          browser.network.wait_for_idle

          frame = browser.at_xpath("//iframe[@id='buttons_frame']").frame
          expect(frame.at_xpath("//button[@id='click_me_123']")).not_to be_nil
        end
      end

      context "#css" do
        it "returns given nodes" do
          browser.go_to("/ferrum/with_js")
          p = browser.css("p#remove_me")

          expect(p.size).to eq(1)
        end

        it "supports within" do
          browser.go_to("/ferrum/with_js")
          p = browser.css("p#with_content").first

          links = browser.css("a", within: p)

          expect(links.size).to eq(1)
          expect(links.first.attribute(:id)).to eq("open-match")
        end

        it "throws an error on an invalid selector" do
          browser.go_to("/ferrum/table")

          expect do
            browser.css("table tr:last")
          end.to raise_error(Ferrum::JavaScriptError)
        end

        it "supports inside a given frame" do
          browser.go_to("/ferrum/frames")
          browser.execute <<-JS
            document.body.innerHTML += "<iframe src='/ferrum/buttons' id='buttons_frame'>"
          JS
          browser.network.wait_for_idle

          frame = browser.at_css("iframe#buttons_frame").frame
          expect(frame.css("button").size).to eq(3)
        end
      end

      context "#at_css" do
        it "returns given nodes" do
          browser.go_to("/ferrum/with_js")
          p = browser.at_css("p#remove_me")

          expect(p).not_to be_nil
        end

        it "supports within" do
          browser.go_to("/ferrum/with_js")
          p = browser.at_css("p#with_content")

          link = browser.at_css("a", within: p)

          expect(link).not_to be_nil
          expect(link.attribute(:id)).to eq("open-match")
        end

        it "throws an error on an invalid selector" do
          browser.go_to("/ferrum/table")

          expect do
            browser.at_css("table tr:last")
          end.to raise_error(Ferrum::JavaScriptError)
        end

        it "supports inside a given frame" do
          browser.go_to("/ferrum/frames")
          browser.execute <<-JS
            document.body.innerHTML += "<iframe src='/ferrum/buttons' id='buttons_frame'>"
          JS
          browser.network.wait_for_idle

          frame = browser.at_css("iframe#buttons_frame").frame
          expect(frame.at_css("button#click_me_123")).not_to be_nil
        end
      end
    end
  end
end
