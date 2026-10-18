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

    it "rejects a modifier key" do
      expect { browser.keyboard.down(:shift) }.to raise_error(ArgumentError, /use keyboard.hold\(:shift\)/)
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

    it "rejects a modifier key" do
      expect { browser.keyboard.up(:Control) }.to raise_error(ArgumentError, /use keyboard.hold\(:Control\)/)
    end
  end

  describe "#hold" do
    before do
      browser.go_to("/type")
      browser.execute(<<~JS)
        window.events = [];
        ["keydown", "keyup", "mousemove", "mousedown", "mouseup"].forEach(type =>
          document.addEventListener(type, e => events.push(`${type}:${e.shiftKey}:${e.ctrlKey}`)));
      JS
    end

    it "holds a modifier for mouse events and releases it after the block" do
      browser.keyboard.hold(:shift) do
        browser.mouse.move(x: 10, y: 10).down.move(x: 50, y: 50, steps: 2).up
      end
      browser.mouse.move(x: 60, y: 60)

      expect(browser.evaluate("events")).to eq(
        %w[keydown:true:false mousemove:true:false mousedown:true:false mousemove:true:false
           mousemove:true:false mouseup:true:false keyup:false:false mousemove:false:false]
      )
      expect(browser.keyboard.held_modifiers).to eq(0)
    end

    it "presses nested modifiers once" do
      browser.keyboard.hold(:shift) do
        browser.keyboard.hold(:shift, :ctrl) { browser.mouse.move(x: 10, y: 10) }
        browser.mouse.move(x: 20, y: 20)
      end

      expect(browser.evaluate("events")).to eq(
        %w[keydown:true:false keydown:true:true mousemove:true:true keyup:true:false
           mousemove:true:false keyup:false:false]
      )
    end

    it "releases modifiers when the block raises" do
      expect do
        browser.keyboard.hold(:shift) { raise "boom" }
      end.to raise_error(RuntimeError, "boom")
      browser.mouse.move(x: 10, y: 10)

      expect(browser.evaluate("events")).to eq(%w[keydown:true:false keyup:false:false mousemove:false:false])
      expect(browser.keyboard.held_modifiers).to eq(0)
    end

    it "returns the block value" do
      expect(browser.keyboard.hold(:shift) { 42 }).to eq(42)
    end

    it "types with the held modifier" do
      input = browser.at_css("#empty_input")

      input.focus
      browser.keyboard.hold(:shift) { browser.keyboard.type("abc") }

      expect(input.value).to eq("ABC")
    end

    it "selects all with the held command modifier" do
      input = browser.at_css("#filled_input")
      modifier = Ferrum::Utils::Platform.mac? ? :meta : :ctrl

      input.focus
      browser.keyboard.hold(modifier) { browser.keyboard.type("a") }
      browser.keyboard.type(:backspace)

      expect(input.value).to eq("")
    end

    it "rejects keys that are not modifiers" do
      expect { browser.keyboard.hold(:enter) { nil } }.to raise_error(ArgumentError, "not a modifier key: :enter")
      expect { browser.keyboard.hold(:shift) }.to raise_error(ArgumentError, "block is required")
    end
  end
end
