# frozen_string_literal: true

describe Ferrum::Node do
  describe "#description" do
    it "returns Chrome's description of the node" do
      browser.go_to("/simple")

      description = browser.at_css("#nav").description

      expect(description).to include("nodeName" => "A", "localName" => "a")
      expect(description["attributes"]).to include("id", "nav")
    end
  end

  describe "#tag_name" do
    before { browser.go_to("/simple") }

    it "returns the lowercased tag name of an element" do
      expect(browser.at_css("#nav").tag_name).to eq("a")
    end

    it "returns the node name of a text node" do
      expect(browser.at_xpath("//a[@id='nav']/text()").tag_name).to eq("#text")
    end
  end

  describe "#node?" do
    before { browser.go_to("/simple") }

    it "returns true for an element" do
      expect(browser.at_css("#nav").node?).to eq(true)
    end

    it "returns false for a text node" do
      expect(browser.at_xpath("//a[@id='nav']/text()").node?).to eq(false)
    end
  end

  describe "#frame" do
    before { browser.go_to("/frame_parent") }

    it "returns the frame an iframe element contains" do
      frame = browser.at_css("#childFrame").frame

      expect(frame).to be_a(Ferrum::Frame)
      expect(frame.at_css("#childBody")).to be_a(described_class)
    end

    it "returns nil for an element that isn't a frame" do
      expect(browser.at_css("#parentBody").frame).to be_nil
    end
  end

  describe "#focus" do
    before { browser.go_to("/form") }

    it "focuses the node" do
      browser.at_css("#form_name").focus

      expect(browser.evaluate("document.activeElement.id")).to eq("form_name")
    end

    it "returns the node" do
      node = browser.at_css("#form_name")

      expect(node.focus).to be(node)
    end
  end

  describe "#blur" do
    before { browser.go_to("/form") }

    it "removes focus from the node" do
      browser.at_css("#form_name").focus.blur

      expect(browser.evaluate("document.activeElement.tagName")).to eq("BODY")
    end

    it "returns the node" do
      node = browser.at_css("#form_name")

      expect(node.blur).to be(node)
    end
  end

  describe "#hover" do
    it "raises NotImplementedError" do
      browser.go_to("/simple")

      expect { browser.at_css("#nav").hover }.to raise_error(Ferrum::NotImplementedError)
    end
  end

  describe "#scroll_into_view" do
    before { browser.go_to("/scroll") }

    it "scrolls the node into the window" do
      link = browser.at_xpath("//a[*//text() = 'Below the fold']")

      link.scroll_into_view

      expect(link.in_viewport?).to eq(true)
    end

    it "scrolls the node into its scrollable parent" do
      link = browser.at_xpath("//a[text() = 'Link outside viewport']")
      box = browser.at_css("#overflow-box")

      link.scroll_into_view

      expect(link.in_viewport?(of: box)).to eq(true)
    end

    it "returns the node" do
      link = browser.at_xpath("//a[*//text() = 'Below the fold']")

      expect(link.scroll_into_view).to be(link)
    end
  end

  describe "#in_viewport?" do
    before { browser.go_to("/scroll") }

    it "returns true for a node within the window" do
      expect(browser.at_css("#overflow-box").in_viewport?).to eq(true)
    end

    it "returns false for a node below the fold" do
      expect(browser.at_xpath("//a[*//text() = 'Below the fold']").in_viewport?).to eq(false)
    end

    it "returns false for a node outside the bounds of the element given in of:" do
      link = browser.at_xpath("//a[text() = 'Link outside viewport']")

      expect(link.in_viewport?).to eq(true)
      expect(link.in_viewport?(of: browser.at_css("#overflow-box"))).to eq(false)
    end
  end

  describe "#click" do
    it "hovers an element before clicking it" do
      browser.go_to("/with_js")

      browser.at_xpath("//a[span[text() = 'Hidden link']]").click

      expect(browser.url).to eq(base_url("/"))
    end

    it "fires a ping request for anchor elements" do
      browser.go_to("/link_with_ping")

      expect(browser.network.traffic.length).to eq(1)
      browser.at_css("a").click

      # first load, load of new url, ping
      expect(browser.network.traffic.length).to be <= 5
    end

    it "returns without waiting for the navigation to load when wait is 0" do
      browser.go_to("/")
      browser.execute(<<~JS)
        document.body.innerHTML = '<a id="slow" href="/really_slow">Slow</a>'
      JS
      started_at = Ferrum::Utils::ElapsedTime.monotonic_time

      browser.at_css("#slow").click(wait: 0)

      expect(Ferrum::Utils::ElapsedTime.monotonic_time - started_at).to be < 1
      expect(browser.network.wait_for_idle(timeout: 5)).to be(true)
      expect(browser.body).to include("really slow page")
    end

    context "when content quads can't be computed" do
      before do
        allow_any_instance_of(described_class).to receive(:content_quads)
          .and_raise(Ferrum::CoordinatesNotFoundError, "Could not compute content quads")
      end

      it "clicks the element by its bounding rect" do
        browser.go_to("/index")

        browser.at_xpath("//a[text()='JS redirect']").click

        expect(browser.body).to include("Hello world")
      end

      it "clicks the element by its bounding rect on a scrolled page" do
        browser.go_to("/long_page")
        link = browser.at_xpath("//a[text() = 'Phasellus blandit velit']").scroll_into_view

        link.click

        expect(browser.url).to eq(base_url("/"))
      end
    end

    it "synchronizes page loads properly" do
      browser.go_to("/index")
      browser.at_xpath("//a[text() = 'JS redirect']").click
      sleep 0.1
      expect(browser.body).to include("Hello world")
    end

    it "raises an error if the element has been removed from the DOM" do
      browser.go_to("/with_js")
      node = browser.at_css("#remove_me")
      expect(node.text).to eq("Remove me")

      browser.at_css("#remove").click

      expect { node.text }.to raise_error(Ferrum::NodeNotFoundError)
    end

    it "raises an error instead of focusing a node from the new document after reload" do
      browser.go_to("/form")
      node = browser.at_css("#customer_email")
      node.focus

      browser.refresh
      browser.at_css("#customer_email").focus
      browser.at_css("#customer_email").blur

      expect { node.focus }.to raise_error(Ferrum::NodeNotFoundError, "node is not trackable")
      expect { node.focus }.to raise_error(Ferrum::NodeNotFoundError, "node is not trackable")
      expect(browser.evaluate("document.activeElement.id")).not_to eq("customer_email")
    end

    it "keeps working after an iframe's content is replaced" do
      browser.go_to("/form")
      node = browser.at_css("#customer_email")
      node.focus
      node.blur

      browser.frame_by(name: "frame").content = "<p>new</p>"
      node.focus

      expect(browser.evaluate("document.activeElement.id")).to eq("customer_email")
    end

    it "keeps working after an accessibility query of the whole page" do
      browser.go_to("/form")
      node = browser.at_css("#customer_email")
      node.focus
      node.blur

      browser.accessibility.query(role: "textbox")
      node.focus

      expect(browser.evaluate("document.activeElement.id")).to eq("customer_email")
    end

    it "raises an error if the element is not visible" do
      browser.go_to("/index")

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
        browser.go_to("/with_js")
      end

      it "clicks properly when then brought in with animate" do
        browser.execute %($("#off-the-left").animate({left: "10"});)

        expect { browser.at_xpath("//a[text() = 'O hai']") }.to_not raise_error
      end
    end

    context "when the element is not in the viewport of parent element" do
      before { page.go_to("/scroll") }

      it "scrolls into view if element outside viewport" do
        link = page.at_xpath("//a[text() = 'Link outside viewport']")
        link.click
        expect(page.url).to eq(base_url("/scroll"))

        expect(link.in_viewport?).to eq(true)
        box = page.at_xpath("//div[@id='overflow-box']")
        expect(link.in_viewport?(of: box)).to eq(false)

        link.scroll_into_view
        expect(link.in_viewport?(of: box)).to eq(true)
        link.click
        expect(page.url).to eq(base_url("/"))
      end

      it "scrolls into view if element below the fold" do
        link = page.at_xpath("//a[*//text() = 'Below the fold']")
        expect(link.in_viewport?).to eq(false)

        link.scroll_into_view

        expect(link.in_viewport?).to eq(true)
        link.click
        expect(page.url).to eq(base_url("/"))
      end
    end

    context "with mode: :double" do
      before { page.go_to("/double_click_test") }

      it "double-clicks the node" do
        log = browser.at_css("#log")

        instructions = %w[one four one two three]
        instructions.each do |instruction|
          browser.at_css("##{instruction}").click(mode: :double, delay: 0.05)
          expect(log.text).to eq(instruction)
        end
      end
    end

    it "raises NodeNotFoundError for a node from before a refresh" do
      browser.go_to("/index")
      shallow_node = browser.at_xpath(".//a")

      browser.refresh
      expect { shallow_node.click }.to raise_error(Ferrum::NodeNotFoundError)

      node = browser.at_xpath(".//a")
      expect { node.click }.not_to raise_error
    end

    it "finishes a form submission that opens an inline PDF" do
      page.go_to("/inline_pdf")
      page.at_css("button").click

      expect(page.url).to eq(base_url("/inline.pdf"))
      expect(page.network.response.content_type).to eq("application/pdf")
    end

    it "keeps waiting for a loading frame when another one is removed" do
      page.go_to("/removed_iframe")
      page.at_css("button").click

      expect(page.evaluate("document.querySelector('iframe').contentWindow.location.pathname"))
        .to eq("/show_cookies/set_cookie_slow")
    end

    it "waits for a navigation it starts after removing a loaded frame" do
      page.go_to("/remove_iframe_and_navigate")
      page.at_css("button").click

      expect(page.evaluate("location.pathname")).to eq("/slow")
    end

    it "clicks a node in a frame with padding" do
      page.go_to
      page.execute <<-JS
      document.body.innerHTML += "<iframe src='/click_test' name='padded_frame' style='padding:100px;'>"
      JS
      sleep 0.5
      frame = page.at_xpath("//iframe[@name = 'padded_frame']").frame

      log = frame.at_css("#log")
      frame.at_css("#one").scroll_into_view.click
      expect(log.text).to eq("one")
    end

    it "clicks a node in a frame nested in a frame" do
      page.go_to

      # The padding on the frame here is to differ the sizes of the two
      # frames, ensuring that their offsets are being calculated separately.
      # This avoids a false positive where the same frame"s offset is
      # calculated twice, but the click still works because both frames had
      # the same offset.
      page.execute <<-JS
      document.body.innerHTML += "<iframe src='/nested_frame_test' name='outer_frame' style='padding:200px'>"
      JS

      sleep 0.5

      inner_frame = page.frame_by(name: "inner_frame")
      log = inner_frame.at_css("#log")
      inner_frame.at_css("#one").scroll_into_view.click
      expect(log.text).to eq("one")
    end

    it "does not block when its handler attaches a lazy iframe" do
      page.go_to("/lazy_iframe")

      expect { page.at_css("#add_iframe").click }.not_to raise_error

      states = page.frames.reject(&:main?).map(&:state)
      expect(states).to eq(%i[stopped_loading stopped_loading stopped_loading])
    end
  end

  describe "#at_xpath" do
    it "searches relatively current node" do
      browser.go_to("/with_js")

      p = browser.at_xpath("//p[@id='with_content']")

      expect(p.at_xpath("a").text).to eq("Open for match")
      expect(p.at_xpath(".//a").text).to eq("Open for match")
    end

    it "searches within a frame" do
      browser.go_to("/form")
      select = browser.at_xpath("//iframe[@name='frame']").frame.at_css("#select")

      expect(select.at_xpath("option[2]").text).to eq("Two")
    end
  end

  describe "#xpath" do
    it "searches relatively current node" do
      browser.go_to("/with_js")

      p = browser.at_xpath("//p[@id='with_content']")
      links = p.xpath("a")

      expect(links.size).to eq(1)
      expect(links.first.text).to eq("Open for match")
    end

    it "works with whitespace nodes" do
      browser.go_to("/ws_node")

      values = browser.xpath("//li//text()").map(&:text)

      expect(values.size).to eq(5)
      expect(values).to eq(["\n        ", "\n          ", "b", "\n        ", "\n      "])
    end

    it "searches within a frame" do
      browser.go_to("/form")
      select = browser.at_xpath("//iframe[@name='frame']").frame.at_css("#select")

      expect(select.xpath("option").map(&:text)).to eq(%w[One Two])
    end
  end

  describe "#at_css" do
    it "searches relatively current node" do
      browser.go_to("/with_js")

      p = browser.at_css("p#with_content")

      expect(p.at_css("a").text).to eq("Open for match")
    end

    it "searches within a frame" do
      browser.go_to("/form")
      select = browser.at_xpath("//iframe[@name='frame']").frame.at_css("#select")

      expect(select.at_css("option:last-child").text).to eq("Two")
    end
  end

  describe "#css" do
    it "searches relatively current node" do
      browser.go_to("/with_js")

      p = browser.at_xpath("//p[@id='with_content']")
      links = p.css("a")

      expect(links.size).to eq(1)
      expect(links.first.text).to eq("Open for match")
    end

    it "searches within a frame" do
      browser.go_to("/form")
      select = browser.at_xpath("//iframe[@name='frame']").frame.at_css("#select")

      expect(select.css("option").map(&:text)).to eq(%w[One Two])
    end
  end

  describe "#selected" do
    before do
      browser.goto("/form")
    end

    it "returns texts of selected options" do
      expect(browser.at_xpath("//*[@id='form_region']").selected.map(&:text)).to eq(["Norway"])
    end

    it "returns selected options within frame" do
      frame = browser.at_xpath("//iframe[@name='frame']").frame

      expect(frame.at_xpath("//*[@id='select']").selected.map(&:text)).to eq(["One"])
    end

    it "returns the first option text when no option is selected" do
      expect(browser.at_xpath("//*[@id='form_title']").selected.map(&:text)).to eq(["Mrs"])
    end

    it "returns an empty array without selected options" do
      expect(browser.at_xpath("//*[@id='form_tendency']").selected.map(&:text)).to eq([])
    end

    it "raises JavaScriptError for an element that isn't a <select>" do
      expect { browser.at_xpath("//*[@id='customer_name']").selected.map(&:text) }
        .to raise_exception(Ferrum::JavaScriptError, /Element is not a <select> element/)
    end
  end

  describe "#select" do
    before do
      browser.goto("/form")
    end

    it "picks option in select by match string argument" do
      expect(browser.at_xpath("//*[@id='form_title']").select("Miss").selected.map(&:text)).to eq(["Miss"])
    end

    def expect_select_to_clear(options)
      expect(browser.at_xpath("//*[@id='form_title']").selected.map(&:text)).to eq(["Mrs"])
      expect(browser.at_xpath("//*[@id='form_title']").select(options).selected.map(&:text)).to eq([])
    end

    it "clears selected options for a text that doesn't exist" do
      expect_select_to_clear("Gotcha")
    end

    it "clears selected options for an empty array" do
      expect_select_to_clear([])
    end

    it "clears selected options for an empty string" do
      expect_select_to_clear("")
    end

    it "picks only the existing options when one of the texts doesn't exist" do
      expect(browser.at_xpath("//*[@id='form_title']").selected.map(&:text)).to eq(["Mrs"])
      expect(browser.at_xpath("//*[@id='form_title']").select(%w[Mrs SQL]).selected.map(&:text)).to eq(["Mrs"])
    end

    it "picks options of a multiple select by an array" do
      expect(browser.at_xpath("//*[@id='form_languages']").select(%w[SQL Ruby]).selected.map(&:text))
        .to eq(%w[Ruby SQL])
    end

    it "picks options of a multiple select by strings" do
      expect(browser.at_xpath("//*[@id='form_languages']").select("SQL", "Ruby").selected.map(&:text))
        .to eq(%w[Ruby SQL])
    end

    it "raises JavaScriptError for an element that isn't a <select>" do
      expect { browser.at_xpath("//*[@id='customer_name']").select("Ruby") }
        .to raise_exception(Ferrum::JavaScriptError, /Element is not a <select> element/)
    end

    it "picks a disabled option" do
      expect(browser.at_xpath("//*[@id='form_title']").select(["Other"]).selected.map(&:text)).to eq(["Other"])
    end

    it "picks an option by its text with by: :text" do
      expect(browser.at_xpath("//select[@id='form_locale']").select("Swedish", by: :text).selected.map(&:value))
        .to eq(["sv"])
    end

    it "picks an option of a select with an empty option" do
      expect(browser.at_xpath("//select[@id='empty_option']").select("AU").selected.map(&:value)).to eq(["AU"])
    end

    it "picks the empty option by an empty value" do
      expect(browser.at_xpath("//select[@id='empty_option']").select("").selected.map(&:value)).to eq([""])
    end

    it "picks the empty option by an empty text" do
      expect(browser.at_xpath("//select[@id='empty_option']").select("", by: :text).selected.map(&:text))
        .to eq([""])
    end

    it "picks option within frame" do
      frame = browser.at_xpath("//iframe[@name='frame']").frame
      expect(frame.at_xpath("//*[@id='select']").select("Two", by: :text).selected.map(&:text)).to eq(["Two"])
    end
  end

  describe "#[]" do
    before { browser.go_to("/attributes_properties") }

    it "returns the property with the given name" do
      expect(browser.at_css(".some_other_class")["innerHTML"]).to eq "<p>foobar</p>"
    end

    it "returns boolean properties as booleans" do
      expect(browser.at_css("input#checked")["checked"]).to be true
      expect(browser.at_css("input#unchecked")["checked"]).to be false
    end
  end

  describe "#==" do
    it "does not equal a node from another page" do
      browser.go_to("/simple")
      el1 = browser.at_css("#nav")
      browser.go_to("/set")
      el2 = browser.at_css("#filled_div")
      expect(el2 == el1).to be_falsey
      expect(el1 == el2).to be_falsey
    end
  end

  describe "#wait_for_stop_moving" do
    it "returns the content quads of a static node" do
      browser.go_to("/simple")

      quads = browser.at_css("#nav").wait_for_stop_moving

      expect(quads.size).to eq(1)
      expect(quads.first.size).to eq(8)
    end

    it "raises NodeMovingError for a node that keeps moving" do
      browser.go_to("/animation")

      expect { browser.at_css(".animated").wait_for_stop_moving(delay: 0.1, attempts: 2) }
        .to raise_error(Ferrum::NodeMovingError, /is moving/)
    end
  end

  describe "#moving?" do
    it "is true for an animated node" do
      browser.go_to("/animation")
      expect(browser.at_css(".animated").moving?).to eq(true)
    end

    it "is false for a static node" do
      browser.go_to("/simple")
      expect(browser.at_css("#nav").moving?).to eq(false)
    end
  end

  describe "#focusable?" do
    before do
      browser.go_to("/form")
    end

    it "returns false for a hidden input" do
      expect(browser.at_css("#hidden_input").focusable?).to eq(false)
    end

    it "returns true for a regular input" do
      expect(browser.at_css("#form_name").focusable?).to eq(true)
    end

    it "leaves the node focused" do
      browser.at_css("#form_name").focusable?
      expect(browser.evaluate("document.activeElement.id")).to eq("form_name")
    end
  end

  describe "#computed_style" do
    before do
      browser.go_to("/computed_style")
    end

    it "returns the computed styles for the node" do
      styles = browser.at_css("#test_node").computed_style

      expect(styles["color"]).to eq("rgb(255, 0, 0)")
      expect(styles["font-weight"]).to eq("700")
    end
  end

  describe "#axnode" do
    before { browser.go_to("/accessibility") }

    it "returns the AXNode for the element" do
      ax = browser.at_css("#submit").axnode

      expect(ax).to be_a(Ferrum::Accessibility::AXNode)
      expect(ax.role).to eq("button")
      expect(ax.name).to eq("Send form")
    end

    it "returns nil for an ignored element" do
      expect(browser.at_css("#hidden").axnode).to be_nil
    end

    it "returns the AXNode of a node in an iframe" do
      browser.go_to("/accessibility_iframe")
      frame_node = browser.page.at_css("iframe").frame.at_css("#child_btn")

      ax = frame_node.axnode

      expect(ax).to be_a(Ferrum::Accessibility::AXNode)
      expect(ax.role).to eq("button")
      expect(ax.name).to eq("Frame button")
    end
  end

  describe "#remove" do
    it "removes node" do
      browser.go_to("/simple")
      node = browser.at_css("#break")

      node.remove

      expect { node.text }.to raise_error(Ferrum::NodeNotFoundError)
    end

    it "raises an error if node is already gone" do
      browser.go_to("/simple")
      node = browser.at_css("#break")
      node.evaluate("this.remove()")

      expect { node.remove }.to raise_error(Ferrum::NodeNotFoundError)
    end
  end

  describe "#exists?" do
    it "returns true" do
      browser.go_to("/simple")
      node = browser.at_css("#break")

      expect(node.exists?).to be_truthy
    end

    it "returns false" do
      browser.go_to("/simple")
      node = browser.at_css("#break")
      node.remove

      expect(node.exists?).to be_falsey
    end
  end

  describe "#value" do
    before { browser.go_to("/form") }

    it "returns the value of an input" do
      expect(browser.at_css("#form_name").value).to eq("John Smith")
    end

    it "returns the value the user typed" do
      input = browser.at_css("#form_name")
      input.execute("this.value = ''")

      input.focus.type("Jane")

      expect(input.value).to eq("Jane")
    end
  end

  describe "#property" do
    before do
      browser.go_to("/attributes_properties")
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

    it "gets a property holding a node as a node, without a warning" do
      el = browser.at_css(".some_other_class p")

      parent = nil
      expect { parent = el.property("parentElement") }.not_to output.to_stderr
      expect(parent.tag_name).to eq("div")
    end

    it "gets a property whose name has a quote" do
      el = browser.at_css(".some_other_class")
      el.execute(%(this["it's"] = 42))

      expect(el.property("it's")).to eq(42)
    end
  end

  describe "#attribute" do
    before { browser.go_to("/attributes_properties") }

    it "returns the attribute as written in markup rather than the live property" do
      link = browser.at_xpath("//a[text() = 'Loop']")

      expect(link.attribute("href")).to eq("/attributes_properties")
      expect(link.property("href")).to eq(base_url("/attributes_properties"))
    end

    it "returns custom attributes" do
      link = browser.at_xpath("//a[text() = 'Loop']")

      expect(link.attribute("data-random")).to eq "42"
      expect(link.attribute("onclick")).to eq "return false;"
    end

    it "returns nil for a missing attribute" do
      expect(browser.at_css("#my_link").attribute("missing")).to be_nil
    end

    it "returns nil for an attribute whose name has a quote" do
      expect(browser.at_css("#my_link").attribute("it's")).to be_nil
    end
  end

  describe "#text" do
    it "skips BR" do
      browser.go_to("/simple")
      node = browser.at_css("#break")

      expect(node.text).to eq("FooBar")
    end

    it "works with valid utf8" do
      browser.go_to("/unicode")
      node = browser.at_css("#valid")

      expect(node.text).to eq("Havregrynskake med marengs og nøtter 😍 såå god!")
    end

    it "works with invalid utf8" do
      browser.go_to("/unicode")
      node = browser.at_css("#invalid")

      expect(node.text).to eq("Havregrynskake med marengs og nøtter \uFFFD")
    end

    it "works with curly utf8" do
      browser.go_to("/unicode")
      node = browser.at_css("#curly")

      expect(node.text).to eq("😀 and ☀")
    end

    it "gets text from an SVG tspan node" do
      browser.go_to("/svg_test")

      expect(browser.at_css("tspan").text).to eq("svg foo")
    end

    it "returns the text with surrounding whitespace stripped" do
      browser.go_to("/filter_text_test")

      expect(browser.at_css("#foo").text).to eq "foo"
    end

    it "keeps all whitespace in the text" do
      browser.go_to("/filter_text_test")

      expect(browser.at_css("#qux").text).to eq " \u00a0 \u3000 qux  \u3000 \u00a0 \u3000  "
    end

    it "raises NodeNotFoundError for a node from a previous page" do
      browser.go_to("/index")
      node = browser.at_xpath(".//a")

      browser.execute "window.location = 'about:blank'"

      expect { node.text }.to raise_error(Ferrum::NodeNotFoundError)
    end
  end

  describe "#inner_text" do
    it "returns BR as new line" do
      browser.go_to("/simple")
      el = browser.at_css("#break")

      expect(el.inner_text).to eq("Foo\nBar")
    end

    it "returns the inner text with stripped whitespace" do
      browser.go_to("/filter_text_test")

      expect(browser.at_css("#bar").inner_text).to eq "bar"
    end

    it "keeps non-breaking spaces in the inner text" do
      browser.go_to("/filter_text_test")

      expect(browser.at_css("#baz").inner_text).to eq "\u00a0baz \u00a0 \u00a0"
    end
  end

  describe "#type" do
    let(:empty_input) { browser.at_css("#empty_input") }

    context "with mixed input" do
      before { browser.go_to("/type") }

      it "sends keys to empty input" do
        empty_input.focus.type("Input")

        expect(empty_input.value).to eq("Input")
      end

      it "sends keys to filled input" do
        input = browser.at_css("#filled_input")

        input.click.type(" appended")

        expect(input.value).to eq("Text appended")
      end

      it "selects all in an input with the command modifier then clears" do
        input = browser.at_css("#filled_input")
        modifier = Ferrum::Utils::Platform.mac? ? :meta : :ctrl

        input.focus.type([modifier, "a"], :backspace)

        expect(input.value).to eq("")
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
        browser.go_to("/date_fields")
        input = browser.at_css("#date_field")

        input.focus.type("02-02-2016")

        expect(input.value).to eq("2016-02-02")
      end

      it "accepts numbers in a maxlength field" do
        browser.go_to("/with_js")
        element = browser.at_css("#change_me_maxlength")

        element.focus.type("100")

        expect(element.value).to eq("100")
      end

      it "accepts negatives in a number field" do
        browser.go_to("/with_js")
        element = browser.at_css("#change_me_number")

        element.focus.type("-100")

        expect(element.value).to eq("-100")
      end
    end

    context "with contenteditable" do
      let(:delete_all) { [[(Ferrum::Utils::Platform.mac? ? :alt : :ctrl), :shift, :right], :backspace] }

      before { browser.go_to("/type") }

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

      it "selects all with the command modifier then clears" do
        input = browser.at_css("#filled_div")
        modifier = Ferrum::Utils::Platform.mac? ? :meta : :ctrl

        input.focus.type([modifier, "a"], :backspace)

        expect(input.text).to eq("")
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

      before { browser.go_to("/type") }

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
        browser.go_to("/with_js")
        change_me.focus.type("Hello!")
      end

      it "fires the change event on blur" do
        change_me.blur

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

      before { browser.go_to("/input_events") }

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

  describe "#select_file" do
    it "selects a file" do
      browser.go_to("/form")
      input = browser.at_css("#form_image")

      input.select_file(File.expand_path(__FILE__))

      expect(input.value).to eq("C:\\fakepath\\node_spec.rb")
    end
  end

  describe "#evaluate" do
    before { browser.go_to("/index") }

    it "binds this to the node" do
      expect(browser.at_xpath(".//a").evaluate("this.getAttribute('href')")).to eq("js_redirect")
    end

    it "accepts named arguments" do
      expect(browser.at_xpath(".//a").evaluate("this.getAttribute(name)", name: "href")).to eq("js_redirect")
    end

    it "resolves nodes returned by a function declaration" do
      expect(browser.at_xpath(".//a").evaluate("function() { return this.parentNode }")).to be_a(Ferrum::Node)
    end
  end

  describe "#evaluate_handle" do
    before { browser.go_to("/index") }

    it "returns a remote object bound to the node" do
      handle = browser.at_xpath(".//a").evaluate_handle("this.attributes")

      expect(handle).to be_a(Ferrum::RemoteObject)
      expect(handle.description).to eq("NamedNodeMap")
    end

    it "returns a node for a node" do
      node = browser.at_xpath(".//a")

      expect(node.evaluate_handle("this")).to eq(node)
    end

    it "returns a primitive as is" do
      expect(browser.at_xpath(".//a").evaluate_handle("this.getAttribute('href')")).to eq("js_redirect")
    end
  end

  describe "#find_position" do
    before { browser.go_to("/simple") }

    def rect
      browser.at_css("#nav").evaluate("this.getBoundingClientRect().toJSON()")
    end

    it "returns the center of the node" do
      x, y = browser.at_css("#nav").find_position

      expect(x).to be_within(0.5).of(rect["left"] + (rect["width"] / 2))
      expect(y).to be_within(0.5).of(rect["top"] + (rect["height"] / 2))
    end

    it "returns the offset from the top-left corner of the node" do
      x, y = browser.at_css("#nav").find_position(x: 5, y: 3)

      expect(x).to be_within(0.5).of(rect["left"] + 5)
      expect(y).to be_within(0.5).of(rect["top"] + 3)
    end

    it "returns the offset from the center of the node with position: :center" do
      x, y = browser.at_css("#nav").find_position(x: 5, y: 3, position: :center)

      expect(x).to be_within(0.5).of(rect["left"] + (rect["width"] / 2) + 5)
      expect(y).to be_within(0.5).of(rect["top"] + (rect["height"] / 2) + 3)
    end

    it "returns the center of the node when only one offset is given" do
      x, y = browser.at_css("#nav").find_position(x: 5)

      expect(x).to be_within(0.5).of(rect["left"] + (rect["width"] / 2))
      expect(y).to be_within(0.5).of(rect["top"] + (rect["height"] / 2))
    end

    it "raises CoordinatesNotFoundError for a hidden node" do
      node = browser.at_css("#nav")
      node.execute("this.style.display = 'none'; this.offsetHeight")

      expect { node.find_position }.to raise_error(Ferrum::CoordinatesNotFoundError)
    end
  end

  describe "#execute" do
    before { browser.go_to("/index") }

    it "calls a named function" do
      browser.execute("function setup() { window.ran = true }")

      expect(browser.evaluate("window.ran")).to be(true)
    end

    it "runs statements" do
      node = browser.at_xpath(".//a")
      node.execute("this.dataset.touched = value", value: "yes")

      expect(node.evaluate("this.dataset.touched")).to eq("yes")
    end
  end
end
