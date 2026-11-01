# frozen_string_literal: true

describe Ferrum::Accessibility::AXNode do
  describe "#value" do
    before { browser.go_to("/accessibility") }

    it "returns the raw CDP value for a range input as a Numeric (Chrome does not stringify it)" do
      ax = browser.page.accessibility.node_for(browser.at_css("#volume"))
      value = ax.value

      # Chrome returns the range value as Integer 7, not the string "7"
      expect(value).to eq(7)
      expect(value).to be_a(Numeric)
    end
  end
end
