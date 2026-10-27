# frozen_string_literal: true

describe Ferrum::Context do
  describe "#windows" do
    it "waits for the window to load" do
      browser.go_to

      browser.execute <<-JS
        window.open("/slow", "popup")
      JS

      popup, = browser.windows(:last)
      expect(popup.body).to include("slow page")
      popup.close
    end

    it "can access a second window of the same name" do
      browser.go_to

      browser.execute <<-JS
        window.open("/simple", "popup")
      JS

      popup, = browser.windows(:last)
      expect(popup.body).to include("Test")
      popup.close

      sleep 0.5 # https://github.com/ChromeDevTools/devtools-protocol/issues/145

      browser.execute <<-JS
        window.open("/simple", "popup")
      JS

      sleep 0.5 # https://github.com/ChromeDevTools/devtools-protocol/issues/145

      same, = browser.windows(:last)
      expect(same.body).to include("Test")
      same.close
    end
  end

  describe "#pages" do
    it "lists pages in the order they were created" do
      pages = Array.new(10) { browser.create_page }

      expect(browser.pages.last(10).map(&:target_id)).to eq(pages.map(&:target_id))
    ensure
      pages&.each(&:close)
    end
  end

  describe "#attach_target" do
    it "reuses the session of an already attached target", :launch do
      browser = Ferrum::Browser.new(base_url: base_url,
                                    extensions: [{ source: "window.runs = (window.runs || 0) + 1" }])
      page = browser.create_page
      page.go_to
      target = browser.targets[page.target_id]
      session_id = target.session_id

      2.times { expect(browser.attach_target(target.id)).to eq(target) }
      page.refresh

      expect(target.session_id).to eq(session_id)
      expect(page.evaluate("window.runs")).to eq(1)
    ensure
      browser&.quit
    end
  end
end
