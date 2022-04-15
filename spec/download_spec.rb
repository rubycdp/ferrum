# frozen_string_literal: true

module Ferrum
  describe Browser do
    context "download support" do
      let(:filename) { "attachment.pdf" }
      let(:browser) do
        Ferrum::Browser.new(
          base_url: Ferrum::Server.server.base_url,
          save_path: save_path
        )
      end

      context "absolute path" do
        let(:save_path) { "/tmp/ferrum" }

        it "saves an attachment" do
          browser.go_to("/#{filename}")

          expect(File.exist?("#{save_path}/#{filename}")).to be true
        ensure
          FileUtils.rm_rf(save_path)
        end
      end

      context "local path" do
        let(:save_path) { "spec/tmp" }

        it "raises an error" do
          expect do
            browser.go_to("/#{filename}")
          end.to raise_error(Ferrum::Error, "supply absolute path as `:save_path` option")
        end
      end
    end
  end
end
