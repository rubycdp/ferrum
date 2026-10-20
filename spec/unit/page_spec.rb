# frozen_string_literal: true

describe Ferrum::Page do
  describe "#set_viewport" do
    it "turns touch emulation off only once after a mobile viewport" do
      page.set_viewport(mobile: true)
      allow(page).to receive(:command).and_call_original

      2.times { page.set_viewport(width: 500, height: 300) }

      expect(page).to have_received(:command)
        .with("Emulation.setTouchEmulationEnabled", enabled: false, maxTouchPoints: 1).once
    end
  end
end
