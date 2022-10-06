# frozen_string_literal: true

module Ferrum
  describe Page do
    describe "#go_to" do
      it "raise an error when a non-existent file was specified" do
        expect do
          page.go_to("file:non-existent")
        end.to raise_error(Ferrum::StatusError)
      end
    end
  end
end
