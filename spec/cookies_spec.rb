# frozen_string_literal: true

describe Ferrum::Cookies do
  describe "#each" do
    context "when a block is given" do
      it "must yield each Cookie" do
        browser.go_to("/set_cookie")

        yielded_cookies = []

        browser.cookies.each do |cookie|
          yielded_cookies << cookie
        end

        expect(yielded_cookies).to eq(
          [
            Ferrum::Cookies::Cookie.new("name" => "stealth",
                                        "value" => "test_cookie",
                                        "domain" => "127.0.0.1",
                                        "path" => "/",
                                        "expires" => -1,
                                        "size" => 18,
                                        "httpOnly" => false,
                                        "secure" => false,
                                        "session" => true,
                                        "priority" => "Medium",
                                        "sameParty" => false,
                                        "sourceScheme" => "NonSecure",
                                        "sourcePort" => server.port)
          ]
        )
      end
    end

    context "when no block is given" do
      it "must return an Enumerator" do
        browser.go_to("/set_cookie")

        expect(browser.cookies.each.to_a).to eq(
          [
            Ferrum::Cookies::Cookie.new("name" => "stealth",
                                        "value" => "test_cookie",
                                        "domain" => "127.0.0.1",
                                        "path" => "/",
                                        "expires" => -1,
                                        "size" => 18,
                                        "httpOnly" => false,
                                        "secure" => false,
                                        "session" => true,
                                        "priority" => "Medium",
                                        "sameParty" => false,
                                        "sourceScheme" => "NonSecure",
                                        "sourcePort" => server.port)
          ]
        )
      end
    end
  end

  describe "#all" do
    it "returns cookie object" do
      browser.go_to("/set_cookie")

      cookies = browser.cookies.all

      expect(cookies).to eq({ "stealth" => Ferrum::Cookies::Cookie.new("name" => "stealth",
                                                                       "value" => "test_cookie",
                                                                       "domain" => "127.0.0.1",
                                                                       "path" => "/",
                                                                       "expires" => -1,
                                                                       "size" => 18,
                                                                       "httpOnly" => false,
                                                                       "secure" => false,
                                                                       "session" => true,
                                                                       "priority" => "Medium",
                                                                       "sameParty" => false,
                                                                       "sourceScheme" => "NonSecure",
                                                                       "sourcePort" => server.port) })
    end
  end

  describe "#[]" do
    it "returns cookie object" do
      browser.go_to("/set_cookie")

      cookie = browser.cookies["stealth"]
      expect(cookie.name).to eq("stealth")
      expect(cookie.value).to eq("test_cookie")
      expect(cookie.domain).to eq("127.0.0.1")
      expect(cookie.path).to eq("/")
      expect(cookie.size).to eq(18)
      expect(cookie.secure?).to be false
      expect(cookie.httponly?).to be false
      expect(cookie.session?).to be true
      expect(cookie.expires).to be_nil
    end
  end

  describe "#set" do
    it "sets cookies" do
      browser.cookies.set(name: "stealth", value: "omg")
      browser.go_to("/get_cookie")
      expect(browser.body).to include("omg")
    end

    it "sets cookies with custom settings" do
      browser.cookies.set(
        name: "stealth",
        value: "omg",
        path: "/ferrum",
        httponly: true,
        samesite: "Strict"
      )

      browser.go_to("/get_cookie")
      expect(browser.body).to_not include("omg")

      browser.go_to("/ferrum/get_cookie")
      expect(browser.body).to include("omg")

      expect(browser.cookies["stealth"].path).to eq("/ferrum")
      expect(browser.cookies["stealth"].httponly?).to be_truthy
      expect(browser.cookies["stealth"].samesite).to eq("Strict")
    end

    it "sets a retrieved cookie" do
      browser.cookies.set(name: "stealth", value: "omg")
      browser.go_to("/get_cookie")
      expect(browser.body).to include("omg")

      cookie = browser.cookies["stealth"]
      browser.cookies.clear
      browser.go_to("/get_cookie")
      expect(browser.body).to_not include("omg")

      browser.cookies.set(cookie)
      browser.go_to("/get_cookie")
      expect(browser.body).to include("omg")
    end

    it "sets a retrieved browser cookie" do
      browser.go_to("/set_cookie")
      cookie = browser.cookies["stealth"]
      browser.go_to("/get_cookie")
      expect(cookie.name).to eq("stealth")
      expect(cookie.value).to eq("test_cookie")
      expect(browser.body).to include("test_cookie")

      browser.cookies.clear
      browser.go_to("/get_cookie")
      expect(browser.body).not_to include("test_cookie")

      browser.cookies.set(cookie)
      browser.go_to("/get_cookie")
      expect(browser.body).to include("test_cookie")
    end

    it "retains the characteristics of the reference cookie" do
      browser.cookies.set(name: "stealth", value: "omg", domain: "site.com")
      expect(browser.cookies["stealth"].name).to eq("stealth")
      expect(browser.cookies["stealth"].value).to eq("omg")
      expect(browser.cookies["stealth"].domain).to eq("site.com")

      cookie = browser.cookies["stealth"]
      browser.cookies.clear
      expect(browser.cookies["stealth"]).to eq(nil)
      browser.cookies.set(cookie)

      expect(browser.cookies["stealth"].name).to eq("stealth")
      expect(browser.cookies["stealth"].value).to eq("omg")
      expect(browser.cookies["stealth"].domain).to eq("site.com")

      browser.cookies.clear
      expect(browser.cookies["stealth"]).to eq(nil)
      browser.cookies.set(cookie.attributes)

      expect(browser.cookies["stealth"].name).to eq("stealth")
      expect(browser.cookies["stealth"].value).to eq("omg")
      expect(browser.cookies["stealth"].domain).to eq("site.com")
    end

    it "prevents side effects for params" do
      cookie_params = { name: "stealth", value: "test_cookie" }
      original_cookie_params = cookie_params.dup

      browser.cookies.set(cookie_params)

      expect(cookie_params).to eq(original_cookie_params)
    end

    it "prevents side effects for cookie object" do
      browser.cookies.set(name: "stealth", value: "omg")
      cookie = browser.cookies["stealth"]
      cookie.instance_variable_set(
        :@attributes,
        { "name" => "stealth", "value" => "test_cookie", "domain" => "site.com" }
      )
      original_attributes = cookie.attributes.dup

      browser.cookies.set(cookie)

      expect(cookie.attributes).to eq(original_attributes)
    end

    it "sets cookies with an expires time" do
      time = Time.at(Time.now.to_i + 10_000)
      browser.go_to
      browser.cookies.set(name: "foo", value: "bar", expires: time)
      expect(browser.cookies["foo"].expires).to eq(time)
    end

    it "sets cookies for given domain" do
      port = server.port
      browser.cookies.set(name: "stealth", value: "127.0.0.1")
      browser.cookies.set(name: "stealth", value: "localhost", domain: "localhost")

      browser.go_to("http://localhost:#{port}/ferrum/get_cookie")
      expect(browser.body).to include("localhost")

      browser.go_to("http://127.0.0.1:#{port}/ferrum/get_cookie")
      expect(browser.body).to include("127.0.0.1")
    end

    it "sets cookies correctly with :domain option when base_url isn't set" do
      browser = Ferrum::Browser.new
      browser.cookies.set(name: "stealth", value: "123456", domain: "localhost")

      port = server.port
      browser.go_to("http://localhost:#{port}/ferrum/get_cookie")
      expect(browser.body).to include("123456")

      browser.go_to("http://127.0.0.1:#{port}/ferrum/get_cookie")
      expect(browser.body).not_to include("123456")
    ensure
      browser&.quit
    end
  end

  describe "#remove" do
    it "removes a cookie" do
      browser.go_to("/set_cookie")

      browser.go_to("/get_cookie")
      expect(browser.body).to include("test_cookie")

      browser.cookies.remove(name: "stealth")

      browser.go_to("/get_cookie")
      expect(browser.body).to_not include("test_cookie")
    end
  end

  describe "#clear" do
    it "clears cookies" do
      browser.go_to("/set_cookie")

      browser.go_to("/get_cookie")
      expect(browser.body).to include("test_cookie")

      browser.cookies.clear

      browser.go_to("/get_cookie")
      expect(browser.body).to_not include("test_cookie")
    end
  end
end
