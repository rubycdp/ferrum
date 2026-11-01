# frozen_string_literal: true

describe Ferrum::Page::Frames do
  describe "#frame_by" do
    it "returns nil for an unknown frame without waiting for it" do
      page.go_to

      frame = page.frame_by(name: "omg")

      expect(frame).to be_nil
    end
  end
end
