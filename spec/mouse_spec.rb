# frozen_string_literal: true

describe Ferrum::Mouse do
  describe "#click" do
    it "supports clicking precise coordinates" do
      browser.go_to("/click_coordinates")
      browser.mouse.click(x: 100, y: 150)
      expect(browser.body).to include("x: 100, y: 150")
    end

    it "has no trouble clicking elements when the size of a document changes" do
      browser.go_to("/long_page")
      browser.at_css("#penultimate").scroll_into_view.click
      browser.execute <<~JS
        el = document.getElementById("penultimate")
        el.parentNode.removeChild(el)
      JS
      browser.at_xpath("//a[text() = 'Phasellus blandit velit']").scroll_into_view.click
      expect(browser.body).to include("Hello")
    end

    it "handles click when the target is in the view, but the document is smaller than the viewport" do
      browser.go_to("/simple")
      browser.at_xpath("//a[text() = 'Link']").click
      expect(browser.body).to include("Hello world")
    end

    it "handles clicks where a parent element has a border" do
      browser.go_to("/table")
      browser.at_xpath("//a[text() = 'Link']").click
      expect(browser.body).to include("Hello world")
    end
  end

  describe "#scroll_by" do
    it "allows the page to be scrolled" do
      browser.go_to("/long_page")
      browser.resize(width: 10, height: 10)
      browser.mouse.scroll_by(30, 70)
      browser.mouse.scroll_by(40, -50)
      browser.mouse.scroll_by(-60, 0)
      expect(
        browser.evaluate("[window.scrollX, window.scrollY]")
      ).to eq([10, 20])
    end
  end

  describe "#scroll_to" do
    it "allows the page to be scrolled" do
      browser.go_to("/long_page")
      browser.resize(width: 10, height: 10)
      browser.mouse.scroll_to(200, 100)
      expect(
        browser.evaluate("[window.scrollX, window.scrollY]")
      ).to eq([200, 100])
    end
  end

  describe "#move" do
    it "sends modifiers" do
      browser.go_to("/simple")
      browser.execute(<<~JS)
        window.events = [];
        ["mousemove", "mousedown", "mouseup"].forEach(type =>
          document.addEventListener(type, e => events.push(`${type}:${e.shiftKey}:${e.altKey}`)));
      JS

      browser.mouse.move(x: 10, y: 10, modifiers: 8)
      browser.keyboard.hold(:shift) { browser.mouse.move(x: 20, y: 20, modifiers: 1) }
      browser.mouse.click(x: 30, y: 30, modifiers: 8)

      expect(browser.evaluate("events")).to eq(
        %w[mousemove:true:false mousemove:false:true mousemove:true:false mousedown:true:false mouseup:true:false]
      )
    end

    it "drags and drops with a button held" do
      browser.go_to("/html5_drag")

      browser.mouse.move(x: 10, y: 10).down.move(x: 250, y: 50, steps: 10).up

      expect(browser.evaluate("window.events")).to eq(%w[dragstart dragover drop dragend])
    end

    it "splits into steps" do
      browser.go_to("/simple")
      browser.mouse.move(x: 100, y: 100)
      browser.execute(<<~JS)
        window.result = [];
        document.addEventListener("mousemove", e => {
          window.result.push([e.clientX, e.clientY]);
        });
      JS

      browser.mouse.move(x: 200, y: 300, steps: 5)

      expect(browser.evaluate("window.result")).to eq([
        [120, 140],
        [140, 180],
        [160, 220],
        [180, 260],
        [200, 300]
      ])
    end

    it "sets buttons property" do
      browser.go_to("/simple")
      browser.mouse.move(x: 100, y: 100)
      browser.execute(<<~JS)
        window.result = [];
        ["move", "up", "down"].forEach(type =>
          document.addEventListener(`mouse${type}`, e => {
            window.result.push([type, e.clientX, e.clientY, e.buttons]);
          })
        );
      JS

      browser.mouse
             .move(x: 101, y: 102)
             .down(button: :left)
             .move(x: 103, y: 104)
             .down(button: :right)
             .move(x: 105, y: 106)
             .up(button: :left)
             .move(x: 107, y: 108)
             .up(button: :right)
             .move(x: 109, y: 110)

      expect(browser.evaluate("window.result")).to eq([
        ["move", 101, 102, 0], # none pressed
        ["down", 101, 102, 1], # left down
        ["move", 103, 104, 1], # left pressed
        ["down", 103, 104, 3], # right down, left pressed
        ["move", 105, 106, 3], # both pressed
        ["up",   105, 106, 2], # left up, right pressed
        ["move", 107, 108, 2], # right pressed
        ["up",   107, 108, 0], # right up
        ["move", 109, 110, 0] # none pressed
      ])
    end
  end

  context "mouse support" do
    before do
      browser.go_to("/click_test")
    end

    after do
      browser.resize(width: 1024, height: 768)
      browser.reset
    end

    it "clicks elements scrolled into view" do
      browser.resize(width: 200, height: 200)
      log = browser.at_css("#log")

      instructions = %w[one four one two three]
      instructions.each do |instruction|
        browser.at_css("##{instruction}").scroll_into_view.click
        expect(log.text).to eq(instruction)
      end
    end

    it "can click an element inside an svg" do
      expect { browser.at_css("#myrect").click }.not_to raise_error
    end
  end
end
