# frozen_string_literal: true

describe Ferrum::Frame do
  describe "#url" do
    it "returns the url of a frame selected by index" do
      page.go_to("/frames")
      frame = page.at_xpath("//iframe").frame
      expect(frame.url).to end_with("/slow")
    end

    it "returns the url of a frame selected by element" do
      page.go_to("/frames")
      frame = page.at_css("iframe[name]").frame
      expect(frame.url).to end_with("/slow")
    end

    it "returns the url of a frame without name or id" do
      page.go_to("/frames")
      frame = page.at_css("iframe:not([name]):not([id])").frame
      expect(frame.url).to end_with("/headers")
    end

    it "returns the url of a frame with id but no name" do
      page.go_to("/frames")
      frame = page.at_css("iframe[id]:not([name])").frame
      expect(frame.url).to end_with("/get_cookie")
    end

    it "returns the url of the main frame of a popup" do
      browser.go_to("/popup_frames")

      browser.at_xpath("//a[text()='pop up']").click

      expect(browser.pages.size).to eq(2)
      opened_page = browser.pages.last
      expect(opened_page.main_frame.url).to end_with("/frames")
    end

    it "returns the url of a frame once it loads" do
      page.go_to
      page.execute <<-JS
      document.body.innerHTML += "<iframe src='/slow' name='frame'>"
      JS

      frame = page.at_xpath("//iframe[@name='frame']").frame
      expect(frame.url).to end_with("/slow")
      expect(frame.body).to include("slow page")

      expect(page.main_frame.url).to end_with("/")
    end

    it "returns the url of a cross-domain frame once it loads" do
      page.go_to("/frames")
      expect(page.url).to eq(base_url("/frames"))
      frame = page.at_xpath("//iframe[@name='frame']").frame

      expect(frame.url).to end_with("/slow")
      expect(frame.body).to include("slow page")

      expect(page.url).to end_with("/frames")
    end

    it "returns the url of the frame, not of the page" do
      page.go_to("/frames")

      frame = page.at_xpath("//iframe").frame
      expect(frame.url).to end_with("/slow")
      expect(page.url).to end_with("/frames")
    end
  end

  describe "#parent" do
    it "returns the parent frame" do
      page.go_to("/frames")
      parent_frame = page.at_xpath("//iframe").frame.parent
      expect(parent_frame.url).to end_with("/frames")
    end
  end

  describe "#content=" do
    it "sets the page content" do
      page.content = "<html><head></head><body>Voila! <a href='#'>Link</a></body></html>"

      expect(page.body).to include("Voila!")
      expect(page.at_css("a").text).to eq("Link")
    end
  end
end
