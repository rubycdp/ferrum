# frozen_string_literal: true

describe Ferrum::Context do
  describe "#windows" do
    it "waits for the window to load" do
      browser.go_to

      browser.execute <<-JS
        window.open("/ferrum/slow", "popup")
      JS

      popup, = browser.windows(:last)
      expect(popup.body).to include("slow page")
      popup.close
    end

    it "can access a second window of the same name" do
      browser.go_to

      browser.execute <<-JS
        window.open("/ferrum/simple", "popup")
      JS

      popup, = browser.windows(:last)
      expect(popup.body).to include("Test")
      popup.close

      sleep 0.5 # https://github.com/ChromeDevTools/devtools-protocol/issues/145

      browser.execute <<-JS
        window.open("/ferrum/simple", "popup")
      JS

      sleep 0.5 # https://github.com/ChromeDevTools/devtools-protocol/issues/145

      same, = browser.windows(:last)
      expect(same.body).to include("Test")
      same.close
    end
  end
end
