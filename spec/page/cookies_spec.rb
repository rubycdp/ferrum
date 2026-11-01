# frozen_string_literal: true

describe Ferrum::Page::Cookies do
  before do
    browser.cookies.set(name: "stealth", value: "local", domain: "127.0.0.1")
    browser.cookies.set(name: "other", value: "elsewhere", domain: "localhost")
  end

  describe "#each" do
    it "returns only the cookies sent to the page" do
      page.go_to("/get_cookie")

      expect(page.cookies.map(&:name)).to eq(["stealth"])
    end

    it "returns nothing before the page has loaded a URL" do
      expect(page.cookies.to_a).to eq([])
    end

    it "returns the cookies sent to the given URLs" do
      page.go_to("/get_cookie")

      expect(page.cookies.each(urls: [base_url.sub("127.0.0.1", "localhost")]).map(&:name)).to eq(["other"])
    end
  end

  describe "#set" do
    it "sets the cookie for the page's host" do
      page.go_to("http://localhost:#{server.port}/get_cookie")

      page.cookies.set(name: "stealth", value: "on localhost")

      domains = browser.cookies.select { |c| c.name == "stealth" }.map(&:domain)
      expect(domains).to contain_exactly("127.0.0.1", "localhost")
    end
  end

  describe "#remove" do
    it "removes the cookie on the page's host" do
      page.go_to("/get_cookie")

      page.cookies.remove(name: "stealth")

      expect(browser.cookies.map(&:name)).to eq(["other"])
    end
  end

  describe "#clear" do
    it "keeps the cookies of other domains" do
      page.go_to("/get_cookie")

      page.cookies.clear

      page.go_to("/get_cookie")
      expect(page.body).not_to include("local")
      expect(browser.cookies.map(&:name)).to eq(["other"])
    end
  end
end
