# frozen_string_literal: true

describe Ferrum::Keyboard do
  describe "#down" do
    before { browser.go_to("/set") }

    it "sends down events from keyboard" do
      expect { browser.keyboard.down("") }.to raise_error(ArgumentError, "empty keys passed")
      expect { browser.keyboard.down([]) }.to raise_error(ArgumentError, "empty keys passed")
      expect { browser.keyboard.down("arghhh") }.not_to raise_error
      expect { browser.keyboard.down(:page_down) }.not_to raise_error
      expect { browser.keyboard.down(1) }.to raise_error(ArgumentError, "unexpected argument")
    end
  end

  describe "#up" do
    before { browser.go_to("/set") }

    it "sends up events from keyboard" do
      expect { browser.keyboard.up("") }.to raise_error(ArgumentError, "empty keys passed")
      expect { browser.keyboard.up([]) }.to raise_error(ArgumentError, "empty keys passed")
      expect { browser.keyboard.up("arghhh") }.not_to raise_error
      expect { browser.keyboard.up(:page_down) }.not_to raise_error
      expect { browser.keyboard.up(1) }.to raise_error(ArgumentError, "unexpected argument")
    end
  end
end
