# frozen_string_literal: true

module Ferrum
  describe Browser do
    context "dragging support", skip: true do
      before { browser.goto("/ferrum/drag") }

      it "supports drag_to" do
        draggable = browser.at_css("#drag_to #draggable")
        droppable = browser.at_css("#drag_to #droppable")

        draggable.drag_to(droppable)
        expect(droppable).to have_content("Dropped")
      end

      it "supports drag_by on native element" do
        draggable = browser.at_css("#drag_by .draggable")

        top_before = browser.evaluate(%($("#drag_by .draggable").position().top))
        left_before = browser.evaluate(%($("#drag_by .draggable").position().left))

        draggable.native.drag_by(15, 15)

        top_after = browser.evaluate(%($("#drag_by .draggable").position().top))
        left_after = browser.evaluate(%($("#drag_by .draggable").position().left))

        expect(top_after).to eq(top_before + 15)
        expect(left_after).to eq(left_before + 15)
      end
    end
  end
end
