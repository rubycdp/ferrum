# frozen_string_literal: true

describe Ferrum::Frame do
  describe "#at_xpath" do
    it "works correctly when JSON is overwritten" do
      page.go_to("/ferrum/index")
      page.execute("JSON = {};")
      expect { page.at_xpath("//a[text() = 'JS redirect']") }.not_to raise_error
    end
  end

  it "supports selection by index" do
    page.go_to("/ferrum/frames")
    frame = page.at_xpath("//iframe").frame
    expect(frame.url).to end_with("/ferrum/slow")
  end

  it "supports selection by element" do
    page.go_to("/ferrum/frames")
    frame = page.at_css("iframe[name]").frame
    expect(frame.url).to end_with("/ferrum/slow")
  end

  it "supports selection by element without name or id" do
    page.go_to("/ferrum/frames")
    frame = page.at_css("iframe:not([name]):not([id])").frame
    expect(frame.url).to end_with("/ferrum/headers")
  end

  it "supports selection by element with id but no name" do
    page.go_to("/ferrum/frames")
    frame = page.at_css("iframe[id]:not([name])").frame
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
    page.go_to
    page.execute <<-JS
      document.body.innerHTML += "<iframe src='/ferrum/slow' name='frame'>"
    JS

    frame = page.at_xpath("//iframe[@name='frame']").frame
    expect(frame.url).to end_with("/ferrum/slow")
    expect(frame.body).to include("slow page")

    expect(page.main_frame.url).to end_with("/")
  end

  it "waits for the cross-domain frame to load" do
    page.go_to("/ferrum/frames")
    expect(page.current_url).to eq(base_url("/ferrum/frames"))
    frame = page.at_xpath("//iframe[@name='frame']").frame

    expect(frame.url).to end_with("/ferrum/slow")
    expect(frame.body).to include("slow page")

    expect(page.current_url).to end_with("/ferrum/frames")
  end

  context "with src == about:blank" do
    it "doesn't hang if no document created" do
      page.go_to
      page.execute <<-JS
        document.body.innerHTML += "<iframe src='about:blank' name='frame'>"
      JS
      frame = page.at_xpath("//iframe[@name='frame']").frame
      expect(frame.body).to eq("<html><head></head><body></body></html>")
    end

    it "doesn't hang if built by JS" do
      page.go_to
      page.execute <<-JS
        document.body.innerHTML += "<iframe src='about:blank' name='frame'>";
        var iframeDocument = document.querySelector("iframe[name='frame']").contentWindow.document;
        var content = "<html><body><p>Hello Frame</p></body></html>";
        iframeDocument.open("text/html", "replace");
        iframeDocument.write(content);
        iframeDocument.close();
      JS
      frame = page.at_xpath("//iframe[@name='frame']").frame
      expect(frame.body).to include("Hello Frame")
    end
  end

  context "with no src attribute" do
    it "doesn't hang if the srcdoc attribute is used" do
      page.go_to
      page.execute <<-JS
        document.body.innerHTML += "<iframe srcdoc='<p>Hello Frame</p>' name='frame'>"
      JS
      frame = page.at_xpath("//iframe[@name='frame']").frame
      expect(frame.body).to include("Hello Frame")
    end

    it "doesn't hang if the frame is filled by JS" do
      page.go_to
      page.execute <<-JS
        document.body.innerHTML += "<iframe id='frame' name='frame'>"
      JS
      page.execute <<-JS
        var iframeDocument = document.querySelector("#frame").contentWindow.document;
        var content = "<html><body><p>Hello Frame</p></body></html>";
        iframeDocument.open("text/html", "replace");
        iframeDocument.write(content);
        iframeDocument.close();
      JS
      frame = page.at_xpath("//iframe[@name='frame']").frame
      expect(frame.body).to include("Hello Frame")
    end
  end

  it "supports clicking in a frame", skip: true do
    page.go_to
    page.execute <<-JS
      document.body.innerHTML += "<iframe src='/ferrum/click_test' name='frame'>"
    JS
    sleep 0.5
    frame = page.at_xpath("//iframe[@name = 'frame']").frame

    log = frame.at_css("#log")
    frame.at_css("#one").click
    expect(log.text).to eq("one")
  end

  it "supports clicking in a frame with padding", skip: true do
    page.go_to
    page.execute <<-JS
      document.body.innerHTML += "<iframe src='/ferrum/click_test' name='padded_frame' style='padding:100px;'>"
    JS
    frame = page.at_xpath("//iframe[@name = 'padded_frame']").frame

    log = frame.at_css("#log")
    frame.at_css("#one").click
    expect(log.text).to eq("one")
  end

  it "supports clicking in a frame nested in a frame", skip: true do
    page.go_to

    # The padding on the frame here is to differ the sizes of the two
    # frames, ensuring that their offsets are being calculated seperately.
    # This avoids a false positive where the same frame"s offset is
    # calculated twice, but the click still works because both frames had
    # the same offset.
    page.execute <<-JS
      document.body.innerHTML += "<iframe src='/ferrum/nested_frame_test' name='outer_frame' style='padding:200px'>"
    JS

    sleep 0.5

    inner_frame = page.frame_by(name: "inner_frame")
    log = inner_frame.at_css("#log")
    inner_frame.at_css("#one").click
    expect(log.text).to eq("one")
  end

  it "does not wait forever for the frame to load" do
    page.go_to

    frame = page.frame_by(name: "omg")

    expect(frame).to be_nil
  end

  it "can get the frames url" do
    page.go_to("/ferrum/frames")

    frame = page.at_xpath("//iframe").frame
    expect(frame.url).to end_with("/ferrum/slow")
    expect(page.current_url).to end_with("/ferrum/frames")
  end

  it "can set page content" do
    page.content = "<html><head></head><body>Voila! <a href='#'>Link</a></body></html>"

    expect(page.body).to include("Voila!")
    expect(page.at_css("a").text).to eq("Link")
  end

  it "gets page doctype" do
    page.go_to("/ferrum/frames")
    expect(page.doctype).to eq("<!DOCTYPE html>")

    doctype40 = %(<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">)
    page.content = "#{doctype40}<html><head></head><body>Voila!</body></html>"
    expect(page.doctype).to eq(doctype40)

    page.content = ""
    expect(page.doctype).to be_nil
  end

  context "#xpath" do
    it "returns given nodes" do
      page.go_to("/ferrum/with_js")
      p = page.xpath("//p[@id='remove_me']")

      expect(p.size).to eq(1)
    end

    it "supports within" do
      page.go_to("/ferrum/with_js")
      p = page.xpath("//p[@id='with_content']").first

      links = page.xpath("./a", within: p)

      expect(links.size).to eq(1)
      expect(links.first.attribute(:id)).to eq("open-match")
    end

    it "throws an error on a wrong xpath" do
      page.go_to("/ferrum/with_js")

      expect do
        page.xpath("#remove_me")
      end.to raise_error(Ferrum::JavaScriptError)
    end

    it "supports inside a given frame" do
      page.go_to("/ferrum/frames")
      page.execute <<-JS
        document.body.innerHTML += "<iframe src='/ferrum/buttons' id='buttons_frame'>"
      JS
      page.network.wait_for_idle

      frame = page.at_xpath("//iframe[@id='buttons_frame']").frame
      expect(frame.xpath("//button").size).to eq(3)
    end
  end

  context "#at_xpath" do
    it "returns given nodes" do
      page.go_to("/ferrum/with_js")
      p = page.at_xpath("//p[@id='remove_me']")

      expect(p).not_to be_nil
    end

    it "supports within" do
      page.go_to("/ferrum/with_js")
      p = page.at_xpath("//p[@id='with_content']")

      link = page.at_xpath("./a", within: p)

      expect(link).not_to be_nil
      expect(link.attribute(:id)).to eq("open-match")
    end

    it "throws an error on a wrong xpath" do
      page.go_to("/ferrum/with_js")

      expect do
        page.at_xpath("#remove_me")
      end.to raise_error(Ferrum::JavaScriptError)
    end

    it "supports inside a given frame" do
      page.go_to("/ferrum/frames")
      page.execute <<-JS
        document.body.innerHTML += "<iframe src='/ferrum/buttons' id='buttons_frame'>"
      JS
      page.network.wait_for_idle

      frame = page.at_xpath("//iframe[@id='buttons_frame']").frame
      expect(frame.at_xpath("//button[@id='click_me_123']")).not_to be_nil
    end
  end

  context "#css" do
    it "returns given nodes" do
      page.go_to("/ferrum/with_js")
      p = page.css("p#remove_me")

      expect(p.size).to eq(1)
    end

    it "supports within" do
      page.go_to("/ferrum/with_js")
      p = page.css("p#with_content").first

      links = page.css("a", within: p)

      expect(links.size).to eq(1)
      expect(links.first.attribute(:id)).to eq("open-match")
    end

    it "throws an error on an invalid selector" do
      page.go_to("/ferrum/table")

      expect do
        page.css("table tr:last")
      end.to raise_error(Ferrum::JavaScriptError)
    end

    it "supports inside a given frame" do
      page.go_to("/ferrum/frames")
      page.execute <<-JS
        document.body.innerHTML += "<iframe src='/ferrum/buttons' id='buttons_frame'>"
      JS
      page.network.wait_for_idle

      frame = page.at_css("iframe#buttons_frame").frame
      expect(frame.css("button").size).to eq(3)
    end
  end

  context "#at_css" do
    it "returns given nodes" do
      page.go_to("/ferrum/with_js")
      p = page.at_css("p#remove_me")

      expect(p).not_to be_nil
    end

    it "supports within" do
      page.go_to("/ferrum/with_js")
      p = page.at_css("p#with_content")

      link = page.at_css("a", within: p)

      expect(link).not_to be_nil
      expect(link.attribute(:id)).to eq("open-match")
    end

    it "throws an error on an invalid selector" do
      page.go_to("/ferrum/table")

      expect do
        page.at_css("table tr:last")
      end.to raise_error(Ferrum::JavaScriptError)
    end

    it "supports inside a given frame" do
      page.go_to("/ferrum/frames")
      page.execute <<-JS
        document.body.innerHTML += "<iframe src='/ferrum/buttons' id='buttons_frame'>"
      JS
      page.network.wait_for_idle

      frame = page.at_css("iframe#buttons_frame").frame
      expect(frame.at_css("button#click_me_123")).not_to be_nil
    end
  end
end
