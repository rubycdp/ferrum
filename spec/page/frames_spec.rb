# frozen_string_literal: true

describe Ferrum::Page::Frames do
  describe "#main_frame" do
    it "returns the top frame of the page" do
      page.go_to("/frame_parent")

      expect(page.main_frame.main?).to be(true)
      expect(page.main_frame.url).to eq(base_url("/frame_parent"))
    end
  end

  describe "#frames" do
    it "returns the main frame and all nested frames" do
      page.go_to("/frame_parent")

      expect(page.frames.map(&:title)).to contain_exactly(
        "This is the parent frame title",
        "This is the child frame title",
        "This is the title of frame one",
        "This is the title of frame two"
      )
    end
  end

  describe "#frame_by" do
    it "returns the frame with the given id" do
      page.go_to("/frame_parent")
      frame = page.at_css("#childFrame").frame

      expect(page.frame_by(id: frame.id)).to equal(frame)
    end

    it "returns the frame with the given name" do
      page.go_to("/frames")

      expect(page.frame_by(name: "frame").url).to end_with("/slow")
    end

    it "returns the frame with the given execution id" do
      page.go_to("/frame_parent")
      frame = page.at_css("#childFrame").frame

      expect(page.frame_by(execution_id: frame.execution_id)).to equal(frame)
    end

    it "returns nil for an unknown frame without waiting for it" do
      page.go_to

      frame = page.frame_by(name: "omg")

      expect(frame).to be_nil
    end
  end
end
