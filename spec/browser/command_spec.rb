# frozen_string_literal: true

module Ferrum
  class Browser
    describe Command do
      it "merges default options" do
        expect(Command.build({}, nil).to_a).to include("--headless")
        expect(Command.build({}, nil).to_a).to include("--disable-web-security")
        expect(Command.build({}, nil).to_a).to include("--remote-debugging-port=0")

        expect(
          Command.build(
            Browser.new(browser_options: { "disable-web-security" => false }).options,
            nil
          ).to_a
        ).to_not include("--disable-web-security")

        expect(
          Command.build(
            Browser.new(browser_options: { "disable-web-security" => nil }).options,
            nil
          ).to_a
        ).to_not include("--disable-web-security")

        expect(
          Command.build(
            Browser.new(
              ignore_default_browser_options: true,
              browser_options: { "headless" => true }
            ).options,
            nil
          ).to_a
        ).to include("--remote-debugging-port=0")

        expect(
          Command.build(
            Browser.new(
              ignore_default_browser_options: true,
              browser_options: { "headless" => true }
            ).options,
            nil
          ).to_a
        ).not_to include("--enable-automation")
      end
    end
  end
end
