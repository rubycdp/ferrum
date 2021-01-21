# frozen_string_literal: true

describe Ferrum::Node do
  describe "#click" do
    it "hovers an element before clicking it" do
      browser.go_to("/ferrum/with_js")

      browser.at_xpath("//a[span[text() = 'Hidden link']]").click

      expect(browser.current_url).to eq(base_url("/"))
    end

    it "does not run into content quads error" do
      browser.go_to("/ferrum/index")

      allow_any_instance_of(Ferrum::Node).to receive(:content_quads)
        .and_raise(Ferrum::CoordinatesNotFoundError, "Could not compute content quads")

      browser.at_xpath("//a[text() = 'JS redirect']").click
      expect(browser.body).to include("Hello world")
    end

    it "synchronizes page loads properly" do
      browser.go_to("/ferrum/index")
      browser.at_xpath("//a[text() = 'JS redirect']").click
      sleep 0.1
      expect(browser.body).to include("Hello world")
    end

    it "raises an error if the element has been removed from the DOM" do
      browser.go_to("/ferrum/with_js")
      node = browser.at_css("#remove_me")
      expect(node.text).to eq("Remove me")

      browser.at_css("#remove").click

      expect { node.text }.to raise_error(Ferrum::NodeNotFoundError)
    end

    it "raises an error if the element is not visible" do
      browser.go_to("/ferrum/index")

      browser.execute <<~JS
        document.querySelector("a[href=js_redirect]").style.display = "none"
      JS

      sleep 0.2 # Wait for node to disappear

      expect do
        browser.at_xpath("//a[text()='JS redirect']").click
      end.to raise_error(
        Ferrum::CoordinatesNotFoundError,
        "Node is either not visible or not an HTMLElement"
      )
    end

    context "when the element is not in the viewport" do
      before do
        browser.go_to("/ferrum/with_js")
      end

      it "raises a MouseEventFailed error", skip: "needs fix" do
        expect do
          browser.at_xpath("//a[text() = 'O hai']").click
        end.to raise_error(Ferrum::MouseEventFailed)
      end

      it "clicks properly when then brought in with animate" do
        browser.execute %($("#off-the-left").animate({left: "10"});)

        expect { browser.at_xpath("//a[text() = 'O hai']") }.to_not raise_error
      end
    end

    context "when the element is not in the viewport of parent element" do
      before { page.go_to("/ferrum/scroll") }

      it "scrolls into view if element outside viewport" do
        link = page.at_xpath("//a[text() = 'Link outside viewport']")
        link.click
        expect(page.current_url).to eq(base_url("/ferrum/scroll"))

        expect(link.in_viewport?).to eq(true)
        box = page.at_xpath("//div[@id='overflow-box']")
        expect(link.in_viewport?(of: box)).to eq(false)

        link.scroll_into_view
        expect(link.in_viewport?(of: box)).to eq(true)
        link.click
        expect(page.current_url).to eq(base_url("/"))
      end

      it "scrolls into view if element below the fold" do
        link = page.at_xpath("//a[*//text() = 'Below the fold']")
        expect(link.in_viewport?).to eq(false)

        link.scroll_into_view

        expect(link.in_viewport?).to eq(true)
        link.click
        expect(page.current_url).to eq(base_url("/"))
      end
    end
  end

  describe "#at_xpath" do
    it "searches relatively current node" do
      browser.go_to("/ferrum/with_js")

      p = browser.at_xpath("//p[@id='with_content']")

      expect(p.at_xpath("a").text).to eq("Open for match")
      expect(p.at_xpath(".//a").text).to eq("Open for match")
    end
  end

  describe "#xpath" do
    it "searches relatively current node" do
      browser.go_to("/ferrum/with_js")

      p = browser.at_xpath("//p[@id='with_content']")
      links = p.xpath("a")

      expect(links.size).to eq(1)
      expect(links.first.text).to eq("Open for match")
    end
  end

  describe "#at_css" do
    it "searches relatively current node" do
      browser.go_to("/ferrum/with_js")

      p = browser.at_css("p#with_content")

      expect(p.at_css("a").text).to eq("Open for match")
    end
  end

  describe "#css" do
    it "searches relatively current node" do
      browser.go_to("/ferrum/with_js")

      p = browser.at_xpath("//p[@id='with_content']")
      links = p.css("a")

      expect(links.size).to eq(1)
      expect(links.first.text).to eq("Open for match")
    end
  end

  describe "#selected" do
    before do
      browser.goto("/ferrum/form")
    end

    it "returns texts of selected options" do
      expect(browser.at_xpath("//*[@id='form_region']").selected.map(&:text)).to eq(["Norway"])
    end

    it "returns selected options within frame" do
      frame = browser.at_xpath("//iframe[@name='frame']").frame

      expect(frame.at_xpath("//*[@id='select']").selected.map(&:text)).to eq(["One"])
    end

    context "when options exists but no selected option" do
      it "returns first option text as default value" do
        expect(browser.at_xpath("//*[@id='form_title']").selected.map(&:text)).to eq(["Mrs"])
      end
    end

    context "when no selected options" do
      it "returns empty array" do
        expect(browser.at_xpath("//*[@id='form_tendency']").selected.map(&:text)).to eq([])
      end
    end

    context "when selector is not <select>" do
      it "raises JavaScriptError with proper message" do
        expect { browser.at_xpath("//*[@id='customer_name']").selected.map(&:text) }
          .to raise_exception(Ferrum::JavaScriptError, /Element is not a <select> element/)
      end
    end
  end

  describe "#select" do
    before do
      browser.goto("/ferrum/form")
    end

    it "picks option in select by match string argument" do
      expect(browser.at_xpath("//*[@id='form_title']").select("Miss").selected.map(&:text)).to eq(["Miss"])
    end

    shared_examples "clears selected options with no exception" do |options|
      it "clears selected options with no exception" do
        expect(browser.at_xpath("//*[@id='form_title']").selected.map(&:text)).to eq(["Mrs"])
        expect(browser.at_xpath("//*[@id='form_title']").select(options).selected.map(&:text)).to eq([])
      end
    end

    context "when option with provided text does not exist" do
      include_examples "clears selected options with no exception", "Gotcha"
    end

    context "when provided empty array" do
      include_examples "clears selected options with no exception", []
    end

    context "when provided empty string" do
      include_examples "clears selected options with no exception", ""
    end

    context "when one of option with provided texts does not exist" do
      it "picks only existed options with no exception" do
        expect(browser.at_xpath("//*[@id='form_title']").selected.map(&:text)).to eq(["Mrs"])
        expect(browser.at_xpath("//*[@id='form_title']").select(%w[Mrs SQL]).selected.map(&:text)).to eq(["Mrs"])
      end
    end

    context "when select has multiple property" do
      it "picks options in select by match arguments as array" do
        expect(browser.at_xpath("//*[@id='form_languages']").select(%w[SQL Ruby]).selected.map(&:text))
          .to eq(%w[Ruby SQL])
      end

      it "picks options in select by match arguments as strings" do
        expect(browser.at_xpath("//*[@id='form_languages']").select("SQL", "Ruby").selected.map(&:text))
          .to eq(%w[Ruby SQL])
      end
    end

    context "when selector is not <select>" do
      it "raises JavaScriptError with proper message" do
        expect { browser.at_xpath("//*[@id='customer_name']").select(anything) }
          .to raise_exception(Ferrum::JavaScriptError, /Element is not a <select> element/)
      end
    end

    context "when provided texts of disabled option" do
      it "picks disabled option with no exception" do
        expect(browser.at_xpath("//*[@id='form_title']").select(["Other"]).selected.map(&:text)).to eq(["Other"])
      end
    end

    context "when option with text and value" do
      it "picks option in select by matched text" do
        expect(browser.at_xpath("//select[@id='form_locale']").select("Swedish", by: :text).selected.map(&:value))
          .to eq(["sv"])
      end
    end

    context "when option with empty text/value" do
      it "picks option in select by match string argument" do
        expect(browser.at_xpath("//select[@id='empty_option']").select("AU").selected.map(&:value)).to eq(["AU"])
      end

      it "picks empty option by match empty value argument" do
        expect(browser.at_xpath("//select[@id='empty_option']").select("").selected.map(&:value)).to eq([""])
      end

      it "picks empty option by match empty text argument" do
        expect(browser.at_xpath("//select[@id='empty_option']").select("", by: :text).selected.map(&:text))
          .to eq([""])
      end
    end

    it "picks option within frame" do
      frame = browser.at_xpath("//iframe[@name='frame']").frame
      expect(frame.at_xpath("//*[@id='select']").select("Two", by: :text).selected.map(&:text)).to eq(["Two"])
    end
  end

  describe "#[]" do
    before do
      browser.go_to("/ferrum/attributes_properties")
    end

    it "gets normalized href" do
      expect(browser.at_xpath("//a[text() = 'Loop']").attribute("href"))
        .to eq("/ferrum/attributes_properties")
    end

    it "gets innerHTML" do
      expect(browser.at_css(".some_other_class").property("innerHTML")).to eq "<p>foobar</p>"
    end

    it "gets attribute" do
      link = browser.at_xpath("//a[text() = 'Loop']")
      expect(link.attribute("data-random")).to eq "42"
      expect(link.attribute("onclick")).to eq "return false;"
    end

    it "gets boolean attributes as booleans" do
      expect(browser.at_css("input#checked").property("checked")).to be true
      expect(browser.at_css("input#unchecked").property("checked")).to be false
    end
  end

  describe "#==" do
    it "does not equal a node from another page" do
      browser.go_to("/ferrum/simple")
      el1 = browser.at_css("#nav")
      browser.go_to("/ferrum/set")
      el2 = browser.at_css("#filled_div")
      expect(el2 == el1).to be_falsey
      expect(el1 == el2).to be_falsey
    end
  end

  describe "#focusable?" do
    before do
      browser.go_to("/ferrum/form")
    end

    context "with hidden input" do
      it { expect(browser.at_css("#hidden_input").focusable?).to eq(false) }
    end

    context "with regular input" do
      it { expect(browser.at_css("#form_name").focusable?).to eq(true) }
    end
  end

  describe "#computed_style" do
    before do
      browser.go_to("/ferrum/computed_style")
    end

    it "returns the computed styles for the node" do
      styles = browser.at_css("#test_node").computed_style

      expect(styles["color"]).to eq("rgb(255, 0, 0)")
      expect(styles["font-weight"]).to eq("700")
    end
  end

  context "whitespace stripping tests", skip: true do
    before do
      browser.go_to("/ferrum/filter_text_test")
    end

    it "gets text" do
      expect(browser.at_css("#foo").text).to eq "foo"
    end

    it "gets text stripped whitespace" do
      expect(browser.at_css("#bar").inner_text).to eq "bar"
    end

    it "gets text stripped whitespace and then converts nbsp to space" do
      expect(browser.at_css("#baz").inner_text).to eq " baz    "
    end

    it "gets text stripped whitespace" do
      expect(browser.at_css("#qux").text).to eq "  \u3000 qux \u3000  "
    end
  end

  describe "#property" do
    before do
      browser.go_to("/ferrum/attributes_properties")
    end

    it "gets property innerHTML" do
      expect(browser.at_css(".some_other_class").property("innerHTML")).to eq "<p>foobar</p>"
    end

    it "gets property outerHTML" do
      el = browser.at_css(".some_other_class")
      expect(el.property("outerHTML"))
        .to eq %(<div class="some_other_class"><p>foobar</p></div>)
    end

    it "gets non existent property" do
      el = browser.at_css(".some_other_class")
      expect(el.property("does_not_exist")).to eq nil
    end
  end

  describe "#text" do
    it "skips BR" do
      browser.go_to("/ferrum/simple")
      el = browser.at_css("#break")

      expect(el.text).to eq("FooBar")
    end

    context "SVG tests" do
      before do
        browser.go_to("/ferrum/svg_test")
      end

      it "gets text from tspan node" do
        expect(browser.at_css("tspan").text).to eq("svg foo")
      end
    end
  end

  describe "#inner_text" do
    it "returns BR as new line" do
      browser.go_to("/ferrum/simple")
      el = browser.at_css("#break")

      expect(el.inner_text).to eq("Foo\nBar")
    end
  end

  describe "#type" do
    let(:empty_input) { browser.at_css("#empty_input") }

    context "with mixed input" do
      before { browser.go_to("/ferrum/type") }

      it "sends keys to empty input" do
        empty_input.focus.type("Input")

        expect(empty_input.value).to eq("Input")
      end

      it "sends keys to filled input" do
        input = browser.at_css("#filled_input")

        input.click.type(" appended")

        expect(input.value).to eq("Text appended")
      end

      it "sends keys to empty textarea" do
        input = browser.at_css("#empty_textarea")

        input.focus.type("Input")

        expect(input.value).to eq("Input")
      end

      it "sends keys to filled textarea" do
        input = browser.at_css("#filled_textarea")

        input.click.type(" appended")

        expect(input.value).to eq("Description appended")
      end

      it "persists focus across multiple calls" do
        input = browser.at_css("#empty_div")

        input.focus.type("helo").type(:Left).type("l")

        expect(input.text).to eq("hello")
      end

      it "sends sequences" do
        empty_input.focus.type([:Shift], "S", [:Alt], "t", "r", "i", "g", :Left, "n")

        expect(empty_input.value).to eq("String")
      end

      it "submits the form with sequence" do
        input = browser.at_css("#without_submit_button input")

        input.focus.type(:Enter)

        expect(input.value).to eq("Submitted")
      end

      it "sends sequences with modifiers and letters" do
        empty_input.focus.type([:Shift, "s"], "t", "r", "i", "n", "g")

        expect(empty_input.value).to eq("String")
      end

      it "moves cursor in front and types char" do
        keys = Ferrum::Utils::Platform.mac? ? %i[Alt Left] : %i[Ctrl Left]

        empty_input.focus.type("t", "r", "i", "n", "g", keys, "s")

        expect(empty_input.value).to eq("string")
      end

      it "selects text and replaces with char" do
        keys = Ferrum::Utils::Platform.mac? ? %i[Alt Shift Left] : %i[Ctrl Shift Left]

        empty_input.focus.type("t", "r", "i", "n", "g", keys, "s")

        expect(empty_input.value).to eq("s")
      end

      it "sends modifiers with sequences" do
        empty_input.focus.type("s", [:Shift, "tring"])

        expect(empty_input.value).to eq("sTRING")
      end

      it "sends modifiers with multiple keys" do
        empty_input.focus.type("helo", %i[Shift Left Left], "llo")

        expect(empty_input.value).to eq("hello")
      end

      it "raises error for unknown keys" do
        expect do
          empty_input.focus.type("abc", :blah)
        end.to raise_error(KeyError, "key not found: :blah")
      end

      it "sets a date fields" do
        browser.go_to("/ferrum/date_fields")
        input = browser.at_css("#date_field")

        input.focus.type("02-02-2016")

        expect(input.value).to eq("2016-02-02")
      end

      it "accepts numbers in a maxlength field" do
        browser.go_to("/ferrum/with_js")
        element = browser.at_css("#change_me_maxlength")

        element.focus.type("100")

        expect(element.value).to eq("100")
      end

      it "accepts negatives in a number field" do
        browser.go_to("/ferrum/with_js")
        element = browser.at_css("#change_me_number")

        element.focus.type("-100")

        expect(element.value).to eq("-100")
      end
    end

    context "with contenteditable" do
      let(:delete_all) { [[(Ferrum::Utils::Platform.mac? ? :alt : :ctrl), :shift, :right], :backspace] }

      before { browser.go_to("/ferrum/type") }

      it "sends keys to empty div" do
        input = browser.at_css("#empty_div")

        input.click.type("Input")

        expect(input.text).to eq("Input")
      end

      it "sends keys to filled div" do
        input = browser.at_css("#filled_div")

        input.click.type(" appended")

        expect(input.text).to eq("Content appended")
      end

      it "sets content" do
        input = browser.at_css("#filled_div")

        input.focus.type(delete_all, "new text")

        expect(input.text).to eq("new text")
      end

      it "sets multiple inputs" do
        input = browser.at_css("#empty_div")
        input.focus.type("new text")
        expect(input.text).to eq("new text")

        input = browser.at_css("#filled_div")
        input.focus.type(delete_all, "replacement text")
        expect(input.text).to eq("replacement text")
      end

      it "sets children content" do
        browser.go_to("/orig_with_js")
        input = browser.at_css("#existing_content_editable_child")

        input.click.type(" WYSIWYG")

        expect(input.text).to eq("Content WYSIWYG")
      end
    end

    context "with correct key codes" do
      let(:events_output) { browser.at_css("#key-events-output") }

      before { browser.go_to("/ferrum/type") }

      it "generates correct events with key codes for modified punctuation" do
        empty_input.focus.type([:shift, "."], [:shift, "t"])

        expect(events_output.text.strip).to eq("keydown:16 keydown:190 keydown:16 keydown:84")
      end

      it "supports snake case specified keys" do
        empty_input.focus.type(:PageUp, :page_up)

        expect(events_output.text.strip).to eq("keydown:33 keydown:33")
      end

      it "supports :control alias for :Ctrl" do
        empty_input.focus.type([:Ctrl, "a"], [:control, "a"])

        expect(events_output.text.strip).to eq("keydown:17 keydown:65 keydown:17 keydown:65")
      end

      it "supports :command alias for :Meta" do
        empty_input.focus.type([:Meta, "z"], [:command, "z"])

        expect(events_output.text.strip).to eq("keydown:91 keydown:90 keydown:91 keydown:90")
      end

      it "supports specified numpad keys" do
        empty_input.focus.type(:numpad2, :numpad8, :divide, :decimal)

        expect(events_output.text.strip).to eq("keydown:98 keydown:104 keydown:111 keydown:110")
      end
    end

    context "with correct changes" do
      let(:change_me) { browser.at_css("#change_me") }

      before do
        browser.go_to("/ferrum/with_js")
        change_me.focus.type("Hello!")
      end

      it "fires the change event", skip: true do
        expect(browser.at_css("#changes").text).to eq("Hello!")
      end

      it "fires the input event" do
        expect(browser.at_css("#changes_on_input").text).to eq("Hello!")
      end

      it "fires the keydown event" do
        expect(browser.at_css("#changes_on_keydown").text).to eq("6")
      end

      it "fires the keyup event" do
        expect(browser.at_css("#changes_on_keyup").text).to eq("6")
      end

      it "fires the keypress event" do
        expect(browser.at_css("#changes_on_keypress").text).to eq("6")
      end

      it "fires the focus event" do
        expect(browser.at_css("#changes_on_focus").text).to eq("Focus")
      end

      it "fires the blur event" do
        change_me.blur

        expect(browser.at_css("#changes_on_blur").text).to eq("Blur")
      end

      it "fires the keydown event before the value is updated" do
        expect(browser.at_css("#value_on_keydown").text).to eq("Hello")
      end

      it "fires the keyup event after the value is updated" do
        expect(browser.at_css("#value_on_keyup").text).to eq("Hello!")
      end

      it "clears the input" do
        keys = Ferrum::Utils::Platform.mac? ? %i[Alt Shift Left] : %i[Ctrl Shift Left]
        change_me.type(2.times.map { keys }, :backspace)

        expect(change_me.value).to eq("")
      end

      it "supports special characters" do
        change_me.type("$52.00")

        expect(change_me.value).to eq("Hello!$52.00")
      end
    end

    context "with correct events" do
      let(:input) { browser.at_css("#input") }
      let(:output) { browser.at_css("#output") }

      before { browser.go_to("/ferrum/input_events") }

      it "calls event handlers in the correct order" do
        input.focus.type("a").blur

        expect(output.text.strip).to eq("keydown keypress input keyup change")
        expect(input.value).to eq("a")
      end

      it "respects preventDefault() calls in keydown handlers" do
        browser.execute "input.addEventListener('keydown', e => e.preventDefault())"
        input.focus.type("a")
        expect(output.text.strip).to eq("keydown keyup")
        expect(input.value).to be_empty
      end

      it "respects preventDefault() calls in keypress handlers" do
        browser.execute "input.addEventListener('keypress', e => e.preventDefault())"
        input.focus.type("a")
        expect(output.text.strip).to eq("keydown keypress keyup")
        expect(input.value).to be_empty
      end

      it "calls event handlers for each character input" do
        input.focus.type("abc").blur
        expect(output.text.strip).to eq("#{(['keydown keypress input keyup'] * 3).join(' ')} change")
        expect(input.value).to eq("abc")
      end

      it "doesn't call the change event if there is no change" do
        input.focus.type("a").blur
        input.focus.type("a")

        expect(output.text.strip).to eq("keydown keypress input keyup change keydown keypress input keyup")
      end
    end
  end

  describe "#attach_file", skip: true do
    it "handles obsolete node" do
      browser.go_to("/ferrum/attach_file")
      browser.attach_file "file", __FILE__
    end

    it "attaches a file when passed a Pathname" do
      filename = Pathname.new("spec/tmp/a_test_pathname").expand_path
      File.write(filename, "text")

      element = browser.at_css("#change_me_file")
      element.set(filename)
      expect(element.value).to eq("C:\\fakepath\\a_test_pathname")
    ensure
      FileUtils.rm_f(filename)
    end
  end

  describe "#drag_to", skip: true do
    before { browser.go_to("/ferrum/drag") }

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

  context "with disappearing node" do
    it "raises an error if the element was on a previous page" do
      browser.go_to("/ferrum/index")
      node = browser.at_xpath(".//a")

      browser.execute "window.location = 'about:blank'"

      expect { node.text }.to raise_error(Ferrum::NodeNotFoundError)
    end
  end
end
