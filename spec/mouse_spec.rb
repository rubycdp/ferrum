# frozen_string_literal: true

describe Ferrum::Mouse do
  describe "#click" do
    it "supports clicking precise coordinates" do
      browser.go_to("/click_coordinates")
      browser.mouse.click(x: 100, y: 150)
      expect(browser.body).to include("x: 100, y: 150")
    end

    it "has no trouble clicking elements when the size of a document changes", skip: true do
      browser.go_to("/long_page")
      browser.at_css("#penultimate").click
      browser.execute <<~JS
        el = document.getElementById("penultimate")
        el.parentNode.removeChild(el)
      JS
      browser.at_xpath("//a[text() = 'Phasellus blandit velit']").click
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

    # Regression specs for [#584]. The bug: Input.dispatchMouseEvent returns
    # before the renderer has run any microtasks queued behind the click (for
    # example, a Stimulus controller registered inside import().then(...)). We
    # can't observe this from a black-box DOM assertion because every ferrum
    # DOM read goes through Runtime.*, which itself drains microtasks. Instead,
    # spy on Page#command and assert that Runtime.evaluate is or isn't issued
    # after the click depending on the option.
    context "with wait_for_pending_js: option" do
      before { browser.go_to("/click_coordinates") }

      it "issues a no-op Runtime.evaluate after the click when true" do
        allow(browser.page).to receive(:command).and_call_original

        browser.mouse.click(x: 100, y: 150, wait_for_pending_js: true)

        expect(browser.page).to have_received(:command).with("Runtime.evaluate", expression: "")
      end

      it "does not issue Runtime.evaluate by default" do
        # Explicitly stub so the spec is deterministic regardless of whether
        # FERRUM_WAIT_FOR_PENDING_JS is set in the developer's environment.
        stub_const("Ferrum::Mouse::WAIT_FOR_PENDING_JS", false)
        allow(browser.page).to receive(:command).and_call_original

        browser.mouse.click(x: 100, y: 150)

        expect(browser.page).not_to have_received(:command).with("Runtime.evaluate", expression: "")
      end

      it "is threaded through Node#click for :left mode" do
        allow(browser.page).to receive(:command).and_call_original

        browser.at_xpath("//body").click(wait_for_pending_js: true)

        expect(browser.page).to have_received(:command).with("Runtime.evaluate", expression: "")
      end

      it "is threaded through Node#click for :right mode" do
        allow(browser.page).to receive(:command).and_call_original

        browser.at_xpath("//body").click(mode: :right, wait_for_pending_js: true)

        expect(browser.page).to have_received(:command).with("Runtime.evaluate", expression: "")
      end

      it "is threaded through Node#click for :double mode" do
        allow(browser.page).to receive(:command).and_call_original

        browser.at_xpath("//body").click(mode: :double, wait_for_pending_js: true)

        expect(browser.page).to have_received(:command).with("Runtime.evaluate", expression: "")
      end
    end

    # The FERRUM_WAIT_FOR_PENDING_JS env var is read once at require time
    # into Mouse::WAIT_FOR_PENDING_JS. Use stub_const to flip it. The
    # Node#click default of `wait_for_pending_js: nil` also resolves to this
    # constant (via Mouse#click's resolution), so one env-var setting covers
    # both layers.
    context "with FERRUM_WAIT_FOR_PENDING_JS env var" do
      it "Ferrum::Mouse::WAIT_FOR_PENDING_JS is false by default",
         skip: (ENV["FERRUM_WAIT_FOR_PENDING_JS"] == "true" ? "skipped: FERRUM_WAIT_FOR_PENDING_JS=true" : false) do
        # Documents the contract: default off unless opted in. Skips (rather
        # than fails) when the developer has opted in via env var, so the
        # ferrum suite doesn't break in environments that exercise that path.
        expect(Ferrum::Mouse::WAIT_FOR_PENDING_JS).to be(false)
      end

      it "flips the default for Mouse#click when set to true" do
        stub_const("Ferrum::Mouse::WAIT_FOR_PENDING_JS", true)
        browser.go_to("/click_coordinates")
        allow(browser.page).to receive(:command).and_call_original

        browser.mouse.click(x: 100, y: 150)

        expect(browser.page).to have_received(:command).with("Runtime.evaluate", expression: "")
      end

      it "flips the default for Node#click when set to true" do
        stub_const("Ferrum::Mouse::WAIT_FOR_PENDING_JS", true)
        browser.go_to("/click_coordinates")
        allow(browser.page).to receive(:command).and_call_original

        browser.at_xpath("//body").click

        expect(browser.page).to have_received(:command).with("Runtime.evaluate", expression: "")
      end

      it "lets an explicit wait_for_pending_js: false at the call site beat the env-var default" do
        stub_const("Ferrum::Mouse::WAIT_FOR_PENDING_JS", true)
        browser.go_to("/click_coordinates")
        allow(browser.page).to receive(:command).and_call_original

        browser.mouse.click(x: 100, y: 150, wait_for_pending_js: false)

        expect(browser.page).not_to have_received(:command).with("Runtime.evaluate", expression: "")
      end

      it "lets an explicit wait_for_pending_js: false on Node#click beat the env-var default" do
        stub_const("Ferrum::Mouse::WAIT_FOR_PENDING_JS", true)
        browser.go_to("/click_coordinates")
        allow(browser.page).to receive(:command).and_call_original

        browser.at_xpath("//body").click(wait_for_pending_js: false)

        expect(browser.page).not_to have_received(:command).with("Runtime.evaluate", expression: "")
      end
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
    it "splits into steps" do
      browser.go_to("/simple")
      browser.mouse.move(x: 100, y: 100)
      browser.evaluate_async(<<~JS, browser.timeout)
        window.result = [];
        document.addEventListener("mousemove", e => {
          window.result.push([e.clientX, e.clientY]);
        });
        arguments[0]();
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
      browser.evaluate_async(<<~JS, browser.timeout)
        window.result = [];
        ["move", "up", "down"].forEach(type =>
          document.addEventListener(`mouse${type}`, e => {
            window.result.push([type, e.clientX, e.clientY, e.buttons]);
          })
        );
        arguments[0]();
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

  context "mouse support", skip: true do
    before do
      browser.go_to("/click_test")
    end

    after do
      browser.resize(width: 1024, height: 768)
      browser.reset
    end

    it "scrolls around so that elements can be clicked" do
      browser.resize(width: 200, height: 200)
      log = browser.at_css("#log")

      instructions = %w[one four one two three]
      instructions.each do |instruction|
        browser.at_css("##{instruction}").click
        browser.screenshot(path: "a.png")
        expect(log.text).to eq(instruction)
      end
    end

    it "fixes some weird layout issue that we are not entirely sure about the reason for" do
      browser.go_to("/datepicker")
      browser.at_css("#datepicker").set("2012-05-11")
      browser.at_xpath("//a[text() = 'some link']").click
    end

    it "can click an element inside an svg" do
      expect { browser.at_css("#myrect").click }.not_to raise_error
    end

    context "with #two overlapping #one" do
      before do
        browser.execute <<-JS
          var two = document.getElementById("two")
          two.style.position = "absolute"
          two.style.left     = "0px"
          two.style.top      = "0px"
        JS
      end

      it "detects if an element is obscured when clicking" do
        expect do
          browser.at_css("#one").click
        end.to raise_error(Ferrum::MouseEventFailed) { |error|
          expect(error.selector).to eq("html body div#two.box")
          expect(error.message).to include("[200.0, 200.0]")
        }
      end

      it "clicks in the center of an element" do
        expect do
          browser.at_css("#one").click
        end.to raise_error(Ferrum::MouseEventFailed) { |error|
          expect(error.position).to eq([200, 200])
        }
      end

      it "clicks in the center of an element within the viewport, if part is outside the viewport" do
        browser.resize(width: 200, height: 200)

        expect do
          browser.at_css("#one").click
        end.to raise_error(Ferrum::MouseEventFailed) { |error|
          expect(error.position.first).to eq(100)
        }
      end
    end

    context "with #svg overlapping #one" do
      before do
        browser.execute <<-JS
          var two = document.getElementById("svg")
          two.style.position = "absolute"
          two.style.left     = "0px"
          two.style.top      = "0px"
        JS
      end

      it "detects if an element is obscured when clicking" do
        expect do
          browser.at_css("#one").click
        end.to raise_error(Ferrum::MouseEventFailed) { |error|
          expect(error.selector).to eq("html body svg#svg.box")
          expect(error.message).to include("[200.0, 200.0]")
        }
      end
    end

    context "with image maps", skip: true do
      before { browser.go_to("/image_map") }

      it "can click" do
        browser.at_css("map[name=testmap] area[shape=circle]").click
        expect(browser).to have_css("#log", text: "circle clicked")
        browser.at_css("map[name=testmap] area[shape=rect]").click
        expect(browser).to have_css("#log", text: "rect clicked")
      end

      it "doesn't click if the associated img is hidden" do
        expect do
          browser.at_css("map[name=testmap2] area[shape=circle]").click
        end.to raise_error(Ferrum::ElementNotFound)
        expect do
          browser.at_css("map[name=testmap2] area[shape=circle]", visible: false).click
        end.to raise_error(Ferrum::MouseEventFailed)
      end
    end
  end
end
