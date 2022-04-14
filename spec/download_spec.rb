# frozen_string_literal: true

module Ferrum
  describe Browser do
    context "download support" do
      let(:browser) do
        Ferrum::Browser.new(
          base_url: Ferrum::Server.server.base_url,
          save_path: "/tmp/ferrum"
        )
      end

      it "saves an attachment" do
        browser.go_to("/attachment.pdf")

        expect(File.exist?("/tmp/ferrum/attachment.pdf")).to be true
      end
    end
  end
end
