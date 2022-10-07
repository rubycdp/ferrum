# frozen_string_literal: true

module Ferrum
  describe Node do
    it "raises an error if the element has been removed from the DOM" do
      browser.go_to("/ferrum/with_js")
      node = browser.at_css("#remove_me")
      expect(node.text).to eq("Remove me")
      browser.at_css("#remove").click
      expect { node.text }.to raise_error(Ferrum::NodeNotFoundError)
    end

    it "raises an error if the element was on a previous page" do
      browser.go_to("/ferrum/index")
      node = browser.at_xpath(".//a")
      browser.execute "window.location = 'about:blank'"
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

    it "hovers an element before clicking it" do
      browser.go_to("/ferrum/with_js")
      browser.at_xpath("//a[span[text() = 'Hidden link']]").click
      expect(browser.current_url).to eq(base_url("/"))
    end

    it "works correctly when JSON is overwritten" do
      browser.go_to("/ferrum/index")
      browser.execute("JSON = {};")
      expect { browser.at_xpath("//a[text() = 'JS redirect']") }.not_to raise_error
    end

    it "#at_xpath searches relatively current node" do
      browser.go_to("/ferrum/with_js")

      p = browser.at_xpath("//p[@id='with_content']")

      expect(p.at_xpath("a").text).to eq("Open for match")
      expect(p.at_xpath(".//a").text).to eq("Open for match")
    end

    it "#xpath searches relatively current node" do
      browser.go_to("/ferrum/with_js")

      p = browser.at_xpath("//p[@id='with_content']")
      links = p.xpath("a")

      expect(links.size).to eq(1)
      expect(links.first.text).to eq("Open for match")
    end

    it "#at_css searches relatively current node" do
      browser.go_to("/ferrum/with_js")

      p = browser.at_css("p#with_content")

      expect(p.at_css("a").text).to eq("Open for match")
    end

    it "#css searches relatively current node" do
      browser.go_to("/ferrum/with_js")

      p = browser.at_xpath("//p[@id='with_content']")
      links = p.css("a")

      expect(links.size).to eq(1)
      expect(links.first.text).to eq("Open for match")
    end

    describe "#selected" do
      before do
        browser.goto("/ferrum/form")
      end

      it "returns texts of selected options" do
        expect(browser.at_xpath("//*[@id='form_region']").selected.map(&:text)).to eq(["Norway"])
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

      it "returns selected options within frame" do
        frame = browser.at_xpath("//iframe[@name='frame']").frame
        expect(frame.at_xpath("//*[@id='select']").selected.map(&:text)).to eq(["One"])
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

    context "when the element is not in the viewport" do
      before do
        browser.go_to("/ferrum/with_js")
      end

      it "raises a MouseEventFailed error", skip: "needs fix" do
        expect do
          browser.at_xpath("//a[text() = 'O hai']").click
        end.to raise_error(Ferrum::MouseEventFailed)
      end

      context "and is then brought in" do
        before do
          browser.execute %($("#off-the-left").animate({left: "10"});)
        end

        it "clicks properly" do
          expect { browser.at_xpath("//a[text() = 'O hai']") }.to_not raise_error
        end
      end
    end

    context "when the element is not in the viewport of parent element", skip: true do
      before do
        browser.go_to("/ferrum/scroll")
      end

      it "scrolls into view", skip: "needs fix" do
        browser.at_xpath("//a[text() = 'Link outside viewport']").click
        expect(browser.current_url).to eq("/")
      end

      it "scrolls into view if scrollIntoViewIfNeeded fails" do
        browser.click_link "Below the fold"
        expect(browser.current_path).to eq("/")
      end
    end

    describe "Node#[]" do
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

    describe "Node#==" do
      it "does not equal a node from another page" do
        browser.go_to("/ferrum/simple")
        el1 = browser.at_css("#nav")
        browser.go_to("/ferrum/set")
        el2 = browser.at_css("#filled_div")
        expect(el2 == el1).to be false
        expect(el1 == el2).to be false
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

    context "supports accessing element properties" do
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

    context "SVG tests" do
      before do
        browser.go_to("/ferrum/svg_test")
      end

      it "gets text from tspan node" do
        expect(browser.at_css("tspan").text).to eq "svg foo"
      end
    end

    it "does not run into content quads error" do
      browser.go_to("/ferrum/index")

      allow_any_instance_of(Node).to receive(:content_quads)
        .and_raise(Ferrum::CoordinatesNotFoundError, "Could not compute content quads")

      browser.at_xpath("//a[text() = 'JS redirect']").click
      expect(browser.body).to include("Hello world")
    end

    it "returns BR as new line in #text" do
      browser.go_to("/ferrum/simple")
      el = browser.at_css("#break")
      expect(el.inner_text).to eq("Foo\nBar")
      expect(browser.at_css("#break").text).to eq("FooBar")
    end

    it "synchronizes page loads properly" do
      browser.go_to("/ferrum/index")
      browser.at_xpath("//a[text() = 'JS redirect']").click
      sleep 0.1
      expect(browser.body).to include("Hello world")
    end

    it "handles obsolete node during an attach_file", skip: true do
      browser.go_to("/ferrum/attach_file")
      browser.attach_file "file", __FILE__
    end
  end
end
