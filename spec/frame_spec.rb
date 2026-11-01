# frozen_string_literal: true

describe Ferrum::Frame do
  describe "#parent_id" do
    it "returns the id of the parent frame" do
      page.go_to("/frame_parent")

      expect(page.at_css("#childFrame").frame.parent_id).to eq(page.main_frame.id)
    end

    it "returns nil for the main frame" do
      page.go_to("/frame_parent")

      expect(page.main_frame.parent_id).to be_nil
    end
  end

  describe "#state" do
    it "returns :stopped_loading once the frame has loaded" do
      page.go_to("/simple")

      expect(page.main_frame.state).to eq(:stopped_loading)
    end

    it "returns :started_loading while the frame loads" do
      page.go_to("/simple")

      page.execute("location.href = '/really_slow'")

      wait_for { page.main_frame.state }.to eq(:started_loading)
    end
  end

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

  describe "#title" do
    it "returns the title of the frame's document" do
      page.go_to("/frame_parent")

      expect(page.main_frame.title).to eq("This is the parent frame title")
      expect(page.at_css("#childFrame").frame.title).to eq("This is the child frame title")
    end
  end

  describe "#main?" do
    it "returns true for the main frame" do
      page.go_to("/frame_parent")

      expect(page.main_frame.main?).to be(true)
    end

    it "returns false for a nested frame" do
      page.go_to("/frame_parent")

      expect(page.at_css("#childFrame").frame.main?).to be(false)
    end
  end

  describe "#idle?" do
    it "returns true once the frame has loaded" do
      page.go_to("/simple")

      expect(page.main_frame.idle?).to be(true)
    end

    it "returns false while the frame loads" do
      page.go_to("/simple")

      page.execute("location.href = '/really_slow'")

      wait_for { page.main_frame.idle? }.to be(false)
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

  describe "#isolated_world" do
    it "returns the same world for the same name" do
      page.go_to("/simple")

      expect(page.main_frame.isolated_world("ferrum")).to equal(page.main_frame.isolated_world("ferrum"))
    end

    it "returns a separate world for another name" do
      page.go_to("/simple")
      page.main_frame.isolated_world("one").execute("window.secret = 'one'")

      expect(page.main_frame.isolated_world("two").evaluate("window.secret")).to be_nil
    end
  end

  describe "#isolated_worlds" do
    it "returns the worlds used so far" do
      page.go_to("/simple")
      page.main_frame.isolated_world("one")
      page.main_frame.isolated_world("two")

      expect(page.main_frame.isolated_worlds.map(&:name)).to include("one", "two")
    end
  end
end
