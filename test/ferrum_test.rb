require "test_helper"

module Ferrum
  class BrowserTest < MiniTest::Unit::TestCase
    def setup
      @browser = Browser.new
    end

    def test_browser
      page = @browser.new_page
      page.navigate("https://www.google.com")
      @browser.close

      assert_equal "OHAI!", @browser
    end
  end
end
