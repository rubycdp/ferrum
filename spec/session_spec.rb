# frozen_string_literal: true

require "spec_helper"

module Ferrum
  describe Browser, skip: true do
    let!(:browser) { Browser.new(base_url: @server.base_url) }

    after { browser.reset }

    describe Ferrum::Node do
      it "raises an error if the element has been removed from the DOM" do
        browser.goto("/ferrum/with_js")
        node = browser.at_css("#remove_me")
        expect(node.text).to eq("Remove me")
        browser.at_css("#remove").click
        expect { node.text }.to raise_error(Ferrum::ObsoleteNode)
      end

      it "raises an error if the element was on a previous page" do
        browser.goto("/ferrum/index")
        node = browser.at_xpath(".//a")
        browser.execute "window.location = 'about:blank'"
        expect { node.text }.to raise_error(Ferrum::ObsoleteNode)
      end

      it "raises an error if the element is not visible" do
        browser.goto("/ferrum/index")
        browser.execute %(document.querySelector("a[href=js_redirect]").style.display = "none")
        expect { browser.at_xpath("//a[text()='JS redirect']").click }.to raise_error(Ferrum::BrowserError, "Could not compute content quads.")
      end

      it "hovers an element" do
        browser.goto("/ferrum/with_js")
        expect(browser.at_css("#hidden_link span").visible?).to be_true
        browser.at_css("#hidden_link").hover
        expect(browser.at_css("#hidden_link span")).to be_visible
      end

      it "hovers an element before clicking it" do
        browser.goto("/ferrum/with_js")
        browser.click_link "Hidden link"
        expect(browser.current_path).to eq("/")
      end

      it "does not raise error when asserting svg elements with a count that is not what is in the dom" do
        browser.goto("/ferrum/with_js")
        expect { browser.has_css?("svg circle", count: 2) }.to_not raise_error
        expect(browser).to_not have_css("svg circle", count: 2)
      end

      context "when someone (*cough* prototype *cough*) messes with Array#toJSON" do
        before do
          browser.goto("/ferrum/index")
          array_munge = <<-JS
          Array.prototype.toJSON = function() {
            return "ohai";
          }
          JS
          browser.execute_script array_munge
        end

        it "gives a proper error" do
          expect { browser.at_css("username") }.to raise_error(Ferrum::ElementNotFound)
        end
      end

      context "when someone messes with JSON" do
        # mootools <= 1.2.4 replaced the native JSON with it's own JSON that didn't have stringify or parse methods
        it "works correctly" do
          browser.goto("/ferrum/index")
          browser.execute_script("JSON = {};")
          expect { browser.find(:link, "JS redirect") }.not_to raise_error
        end
      end

      context "when the element is not in the viewport" do
        before do
          browser.goto("/ferrum/with_js")
        end

        it "raises a MouseEventFailed error" do
          expect { browser.click_link("O hai") }
            .to raise_error(Ferrum::MouseEventFailed)
        end

        context "and is then brought in" do
          before do
            browser.execute_script %Q($("#off-the-left").animate({left: "10"});)
          end

          it "clicks properly" do
            expect { browser.click_link "O hai" }.to_not raise_error
          end
        end
      end
    end

    context "when the element is not in the viewport of parent element" do
      before do
        browser.goto("/ferrum/scroll")
      end

      it "scrolls into view" do
        browser.click_link "Link outside viewport"
        expect(browser.current_path).to eq("/")
      end

      it "scrolls into view if scrollIntoViewIfNeeded fails" do
        browser.click_link "Below the fold"
        expect(browser.current_path).to eq("/")
      end
    end

    describe "Node#select" do
      before do
        browser.goto("/ferrum/with_js")
      end

      context "when selected option is not in optgroup" do
        before do
          browser.find(:select, "browser").find(:option, "Firefox").select_option
        end

        it "fires the focus event" do
          expect(browser.at_css("#changes_on_focus").text).to eq("Browser")
        end

        it "fire the change event" do
          expect(browser.at_css("#changes").text).to eq("Firefox")
        end

        it "fires the blur event" do
          expect(browser.at_css("#changes_on_blur").text).to eq("Firefox")
        end

        it "fires the change event with the correct target" do
          expect(browser.at_css("#target_on_select").text).to eq("SELECT")
        end
      end

      context "when selected option is in optgroup" do
        before do
          browser.find(:select, "browser").find(:option, "Safari").select_option
        end

        it "fires the focus event" do
          expect(browser.at_css("#changes_on_focus").text).to eq("Browser")
        end

        it "fire the change event" do
          expect(browser.at_css("#changes").text).to eq("Safari")
        end

        it "fires the blur event" do
          expect(browser.at_css("#changes_on_blur").text).to eq("Safari")
        end

        it "fires the change event with the correct target" do
          expect(browser.at_css("#target_on_select").text).to eq("SELECT")
        end
      end
    end

    describe "Node#set" do
      before do
        browser.goto("/ferrum/with_js")
        browser.at_css("#change_me").set("Hello!")
      end

      it "fires the change event" do
        expect(browser.at_css("#changes").text).to eq("Hello!")
      end

      it "fires the input event" do
        expect(browser.at_css("#changes_on_input").text).to eq("Hello!")
      end

      it "accepts numbers in a maxlength field" do
        element = browser.at_css("#change_me_maxlength")
        element.set 100
        expect(element.value).to eq("100")
      end

      it "accepts negatives in a number field" do
        element = browser.at_css("#change_me_number")
        element.set(-100)
        expect(element.value).to eq("-100")
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
        expect(browser.at_css("#changes_on_blur").text).to eq("Blur")
      end

      it "fires the keydown event before the value is updated" do
        expect(browser.at_css("#value_on_keydown").text).to eq("Hello")
      end

      it "fires the keyup event after the value is updated" do
        expect(browser.at_css("#value_on_keyup").text).to eq("Hello!")
      end

      it "clears the input before setting the new value" do
        element = browser.at_css("#change_me")
        element.set ""
        expect(element.value).to eq("")
      end

      it "supports special characters" do
        element = browser.at_css("#change_me")
        element.set "$52.00"
        expect(element.value).to eq("$52.00")
      end

      it "attaches a file when passed a Pathname" do
        begin
          filename = Pathname.new("spec/tmp/a_test_pathname").expand_path
          File.open(filename, "w") { |f| f.write("text") }

          element = browser.at_css("#change_me_file")
          element.set(filename)
          expect(element.value).to eq("C:\\fakepath\\a_test_pathname")
        ensure
          FileUtils.rm_f(filename)
        end
      end
    end

    describe "Node#visible" do
      before do
        browser.goto("/ferrum/visible")
      end

      it "considers display: none to not be visible" do
        expect(browser.at_css("li", text: "Display None", visible: false).visible?).to be false
      end

      it "considers visibility: hidden to not be visible" do
        expect(browser.at_css("li", text: "Hidden", visible: false).visible?).to be false
      end

      it "considers opacity: 0 to not be visible" do
        expect(browser.at_css("li", text: "Transparent", visible: false).visible?).to be false
      end

      it "element with all children hidden returns empty text" do
        expect(browser.at_css("div").text).to eq("")
      end
    end

    describe "Node#checked?" do
      before do
        browser.goto("/ferrum/attributes_properties")
      end

      it "is a boolean" do
        expect(browser.find_field("checked").checked?).to be true
        expect(browser.find_field("unchecked").checked?).to be false
      end
    end

    describe "Node#[]" do
      before do
        browser.goto("/ferrum/attributes_properties")
      end

      it "gets normalized href" do
        expect(browser.find(:link, "Loop")["href"]).to eq("http://#{browser.server.host}:#{browser.server.port}/ferrum/attributes_properties")
      end

      it "gets innerHTML" do
        expect(browser.at_css(".some_other_class")["innerHTML"]).to eq "<p>foobar</p>"
      end

      it "gets attribute" do
        link = browser.find(:link, "Loop")
        expect(link["data-random"]).to eq "42"
        expect(link["onclick"]).to eq "return false;"
      end

      it "gets boolean attributes as booleans" do
        expect(browser.find_field("checked")["checked"]).to be true
        expect(browser.find_field("unchecked")["checked"]).to be false
      end
    end

    describe "Node#==" do
      it "does not equal a node from another page" do
        browser.goto("/ferrum/simple")
        @elem1 = browser.at_css("#nav")
        browser.goto("/ferrum/set")
        @elem2 = browser.at_css("#filled_div")
        expect(@elem2 == @elem1).to be false
        expect(@elem1 == @elem2).to be false
      end
    end

    it "has no trouble clicking elements when the size of a document changes" do
      browser.goto("/ferrum/long_page")
      browser.at_css("#penultimate").click
      browser.execute_script <<-JS
        el = document.getElementById("penultimate")
        el.parentNode.removeChild(el)
      JS
      browser.click_link("Phasellus blandit velit")
      expect(browser).to have_content("Hello")
    end

    it "handles clicks where the target is in view, but the document is smaller than the viewport" do
      browser.goto("/ferrum/simple")
      browser.click_link "Link"
      expect(browser).to have_content("Hello world")
    end

    it "handles clicks where a parent element has a border" do
      browser.goto("/ferrum/table")
      browser.click_link "Link"
      expect(browser).to have_content("Hello world")
    end

    it "handles evaluate_script values properly" do
      expect(browser.evaluate_script("null")).to be_nil
      expect(browser.evaluate_script("false")).to be false
      expect(browser.evaluate_script("true")).to be true
      expect(browser.evaluate_script("undefined")).to eq(nil)

      expect(browser.evaluate_script("3;")).to eq(3)
      expect(browser.evaluate_script("31337")).to eq(31337)
      expect(browser.evaluate_script(%("string"))).to eq("string")
      expect(browser.evaluate_script(%({foo: "bar"}))).to eq("foo" => "bar")

      expect(browser.evaluate_script("new Object")).to eq({})
      expect(browser.evaluate_script("new Date(2012, 0).toDateString()")).to eq("Sun Jan 01 2012")
      expect(browser.evaluate_script("new Object({a: 1})")).to eq({"a" => 1})
      expect(browser.evaluate_script("new Array")).to eq([])
      expect(browser.evaluate_script("new Function")).to eq({})

      expect { browser.evaluate_script(%(throw "smth")) }.to raise_error(Ferrum::JavaScriptError)
    end

    it "ignores cyclic structure errors in evaluate_script" do
      code = <<-JS
        (function() {
          var a = {};
          var b = {};
          var c = {};
          c.a = a;
          a.a = a;
          a.b = b;
          a.c = c;
          return a;
        })()
      JS

      expect(browser.evaluate_script(code)).to eq("(cyclic structure)")
    end

    it "synchronises page loads properly" do
      browser.goto("/ferrum/index")
      browser.click_link "JS redirect"
      sleep 0.1
      expect(browser.html).to include("Hello world")
    end

    context "click tests" do
      before do
        browser.goto("/ferrum/click_test")
      end

      after do
        browser.driver.resize(1024, 768)
        browser.driver.reset!
      end

      it "scrolls around so that elements can be clicked" do
        browser.driver.resize(200, 200)
        log = browser.at_css("#log")

        instructions = %w[one four one two three]
        instructions.each do |instruction|
          browser.at_css("##{instruction}").click
          expect(log.text).to eq(instruction)
        end
      end

      it "fixes some weird layout issue that we are not entirely sure about the reason for" do
        browser.goto("/ferrum/datepicker")
        browser.at_css("#datepicker").set("2012-05-11")
        browser.click_link "some link"
      end

      it "can click an element inside an svg" do
        expect { browser.at_css("#myrect").click }.not_to raise_error
      end

      context "with #two overlapping #one" do
        before do
          browser.execute_script <<-JS
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
          browser.driver.resize(200, 200)

          expect do
            browser.at_css("#one").click
          end.to raise_error(Ferrum::MouseEventFailed) { |error|
            expect(error.position.first).to eq(100)
          }
        end
      end

      context "with #svg overlapping #one" do
        before do
          browser.execute_script <<-JS
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
        before { browser.goto("/ferrum/image_map") }

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

    context "double click tests" do
      before do
        browser.goto("/ferrum/double_click_test")
      end

      it "double clicks properly" do
        browser.driver.resize(200, 200)
        log = browser.at_css("#log")

        instructions = %w[one four one two three]
        instructions.each do |instruction|
          browser.at_css("##{instruction}").base.double_click
          expect(log.text).to eq(instruction)
        end
      end
    end

    context "status code support", status_code_support: true do
      it "determines status code when an user goes to a page by using a link on it" do
        browser.goto("/ferrum/with_different_resources")

        browser.click_link "Go to 500"

        expect(browser.status_code).to eq(500)
      end

      it "determines properly status code when an user goes through a few pages" do
        browser.goto("/ferrum/with_different_resources")

        browser.click_link "Go to 201"
        browser.click_link "Do redirect"
        browser.click_link "Go to 402"

        expect(browser.status_code).to eq(402)
      end
    end

    it "returns BR as new line in #text" do
      browser.goto("/ferrum/simple")
      expect(browser.at_css("#break").text).to eq("Foo\nBar")
    end

    it "handles hash changes" do
      browser.goto("/#omg")
      expect(browser.current_url).to match(%r{/#omg$})
      browser.execute_script <<-JS
        window.onhashchange = function() { window.last_hashchange = window.location.hash }
      JS
      browser.goto("/#foo")
      expect(browser.current_url).to match(%r{/#foo$})
      expect(browser.evaluate_script("window.last_hashchange")).to eq("#foo")
    end

    context "current_url" do
      let(:request_uri) { URI.parse(browser.current_url).request_uri }

      it "supports whitespace characters" do
        browser.goto("/ferrum/arbitrary_path/200/foo%20bar%20baz")
        expect(browser.current_path).to eq("/ferrum/arbitrary_path/200/foo%20bar%20baz")
      end

      it "supports escaped characters" do
        browser.goto("/ferrum/arbitrary_path/200/foo?a%5Bb%5D=c")
        expect(request_uri).to eq("/ferrum/arbitrary_path/200/foo?a%5Bb%5D=c")
      end

      it "supports url in parameter" do
        browser.goto("/ferrum/arbitrary_path/200/foo%20asd?a=http://example.com/asd%20asd")
        expect(request_uri).to eq("/ferrum/arbitrary_path/200/foo%20asd?a=http://example.com/asd%20asd")
      end

      it "supports restricted characters ' []:/+&='" do
        browser.goto("/ferrum/arbitrary_path/200/foo?a=%20%5B%5D%3A%2F%2B%26%3D")
        expect(request_uri).to eq("/ferrum/arbitrary_path/200/foo?a=%20%5B%5D%3A%2F%2B%26%3D")
      end

      it "returns about:blank when on about:blank" do
        browser.goto("about:blank")
        expect(browser.current_url).to eq("about:blank")
      end
    end

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

        top_before = browser.evaluate_script(%($("#drag_by .draggable").position().top))
        left_before = browser.evaluate_script(%($("#drag_by .draggable").position().left))

        draggable.native.drag_by(15, 15)

        top_after = browser.evaluate_script(%($("#drag_by .draggable").position().top))
        left_after = browser.evaluate_script(%($("#drag_by .draggable").position().left))

        expect(top_after).to eq(top_before + 15)
        expect(left_after).to eq(left_before + 15)
      end
    end

    context "window switching support" do
      it "waits for the window to load" do
        browser.goto

        popup = browser.window_opened_by do
          browser.execute_script <<-JS
            window.open("/ferrum/slow", "popup")
          JS
        end

        browser.within_window(popup) do
          expect(browser.html).to include("slow page")
        end
        popup.close
      end

      it "can access a second window of the same name" do
        browser.goto

        popup = browser.window_opened_by do
          browser.execute_script <<-JS
            window.open("/ferrum/simple", "popup")
          JS
        end
        browser.within_window(popup) do
          expect(browser.html).to include("Test")
        end
        popup.close

        sleep 0.5 # https://github.com/ChromeDevTools/devtools-protocol/issues/145

        same = browser.window_opened_by do
          browser.execute_script <<-JS
            window.open("/ferrum/simple", "popup")
          JS
        end
        browser.within_window(same) do
          expect(browser.html).to include("Test")
        end
        same.close
      end
    end

    context "frame support" do
      it "supports selection by index" do
        browser.goto("/ferrum/frames")

        browser.within_frame 0 do
          expect(browser.driver.frame_url).to end_with("/ferrum/slow")
        end
      end

      it "supports selection by element" do
        browser.goto("/ferrum/frames")
        frame = browser.at_css("iframe[name]")

        browser.within_frame(frame) do
          expect(browser.driver.frame_url).to end_with("/ferrum/slow")
        end
      end

      it "supports selection by element without name or id" do
        browser.goto("/ferrum/frames")
        frame = browser.at_css("iframe:not([name]):not([id])")

        browser.within_frame(frame) do
          expect(browser.driver.frame_url).to end_with("/ferrum/headers")
        end
      end

      it "supports selection by element with id but no name" do
        browser.goto("/ferrum/frames")
        frame = browser.at_css("iframe[id]:not([name])")

        browser.within_frame(frame) do
          expect(browser.driver.frame_url).to end_with("/ferrum/get_cookie")
        end
      end

      it "waits for the frame to load" do
        browser.goto

        browser.execute_script <<-JS
          document.body.innerHTML += "<iframe src='/ferrum/slow' name='frame'>"
        JS

        browser.within_frame "frame" do
          expect(browser.driver.frame_url).to end_with("/ferrum/slow")
          expect(browser.html).to include("slow page")
        end
        expect(URI.parse(browser.driver.frame_url).path).to eq("/")
      end

      it "waits for the cross-domain frame to load" do
        browser.goto("/ferrum/frames")
        expect(browser.current_path).to eq("/ferrum/frames")

        browser.within_frame "frame" do
          expect(browser.driver.frame_url).to end_with("/ferrum/slow")
          expect(browser.body).to include("slow page")
        end

        expect(browser.driver.frame_url).to end_with("/ferrum/frames")
      end

      context "with src == about:blank" do
        it "doesn't hang if no document created" do
          browser.goto
          browser.execute_script <<-JS
            document.body.innerHTML += "<iframe src='about:blank' name='frame'>"
          JS
          browser.within_frame "frame" do
            expect(browser).to have_no_xpath("/html/body/*")
          end
        end

        it "doesn't hang if built by JS" do
          browser.goto
          browser.execute_script <<-JS
            document.body.innerHTML += "<iframe src='about:blank' name='frame'>";
            var iframeDocument = document.querySelector("iframe[name='frame']").contentWindow.document;
            var content = "<html><body><p>Hello Frame</p></body></html>";
            iframeDocument.open("text/html", "replace");
            iframeDocument.write(content);
            iframeDocument.close();
          JS

          browser.within_frame "frame" do
            expect(browser).to have_content("Hello Frame")
          end
        end
      end

      context "with no src attribute" do
        it "doesn't hang if the srcdoc attribute is used" do
          browser.goto
          browser.execute_script <<-JS
            document.body.innerHTML += "<iframe srcdoc='<p>Hello Frame</p>' name='frame'>"
          JS

          browser.within_frame "frame" do
            expect(browser).to have_content("Hello Frame", wait: false)
          end
        end

        it "doesn't hang if the frame is filled by JS" do
          browser.goto
          browser.execute_script <<-JS
            document.body.innerHTML += "<iframe id='frame' name='frame'>"
          JS
          browser.execute_script <<-JS
            var iframeDocument = document.querySelector("#frame").contentWindow.document;
            var content = "<html><body><p>Hello Frame</p></body></html>";
            iframeDocument.open("text/html", "replace");
            iframeDocument.write(content);
            iframeDocument.close();
          JS

          browser.within_frame "frame" do
            expect(browser).to have_content("Hello Frame", wait: false)
          end
        end
      end

      it "supports clicking in a frame" do
        browser.goto

        browser.execute_script <<-JS
          document.body.innerHTML += "<iframe src='/ferrum/click_test' name='frame'>"
        JS

        browser.within_frame "frame" do
          log = browser.at_css("#log")
          browser.at_css("#one").click
          expect(log.text).to eq("one")
        end
      end

      it "supports clicking in a frame with padding" do
        browser.goto

        browser.execute_script <<-JS
          document.body.innerHTML += "<iframe src='/ferrum/click_test' name='padded_frame' style='padding:100px;'>"
        JS

        browser.within_frame "padded_frame" do
          log = browser.at_css("#log")
          browser.at_css("#one").click
          expect(log.text).to eq("one")
        end
      end

      it "supports clicking in a frame nested in a frame" do
        browser.goto

        # The padding on the frame here is to differ the sizes of the two
        # frames, ensuring that their offsets are being calculated seperately.
        # This avoids a false positive where the same frame"s offset is
        # calculated twice, but the click still works because both frames had
        # the same offset.
        browser.execute_script <<-JS
          document.body.innerHTML += "<iframe src='/ferrum/nested_frame_test' name='outer_frame' style='padding:200px'>"
        JS

        browser.within_frame "outer_frame" do
          browser.within_frame "inner_frame" do
            log = browser.at_css("#log")
            browser.at_css("#one").click
            expect(log.text).to eq("one")
          end
        end
      end

      it "does not wait forever for the frame to load" do
        browser.goto

        expect do
          browser.within_frame("omg") {}
        end.to(raise_error do |e|
          expect(e).to be_a(Ferrum::FrameNotFound)
        end)
      end
    end

    it "handles obsolete node during an attach_file" do
      browser.goto("/ferrum/attach_file")
      browser.attach_file "file", __FILE__
    end

    it "throws an error on an invalid selector" do
      browser.goto("/ferrum/table")
      expect { browser.at_css("table tr:last") }.to raise_error(Ferrum::InvalidSelector)
    end

    it "throws an error on wrong xpath" do
      browser.goto("/ferrum/with_js")
      expect { browser.at_xpath("#remove_me") }.to raise_error(Ferrum::InvalidSelector)
    end

    it "should submit form" do
      browser.goto("/ferrum/type")
      browser.at_css("#without_submit_button").trigger("submit")
      expect(browser.at_css("#without_submit_button input").value).to eq("Submitted")
    end

    context "whitespace stripping tests" do
      before do
        browser.goto("/ferrum/filter_text_test")
      end

      it "gets text" do
        expect(browser.at_css("#foo").text).to eq "foo"
      end

      it "gets text stripped whitespace" do
        expect(browser.at_css("#bar").text).to eq "bar"
      end

      it "gets text stripped whitespace and then converts nbsp to space" do
        expect(browser.at_css("#baz").text).to eq " baz    "
      end

      it "gets text stripped whitespace" do
        expect(browser.at_css("#qux").text).to eq "  \u3000 qux \u3000  "
      end
    end

    context "supports accessing element properties" do
      before do
        browser.goto("/ferrum/attributes_properties")
      end

      it "gets property innerHTML" do
        expect(browser.at_css(".some_other_class").native.property("innerHTML")).to eq "<p>foobar</p>"
      end

      it "gets property outerHTML" do
        expect(browser.at_css(".some_other_class").native.property("outerHTML")).to eq %(<div class="some_other_class"><p>foobar</p></div>)
      end

      it "gets non existent property" do
        expect(browser.at_css(".some_other_class").native.property("does_not_exist")).to eq nil
      end
    end

    it "allows access to element attributes" do
      browser.goto("/ferrum/attributes_properties")
      expect(browser.at_css("#my_link").native.attributes).to eq(
        "href" => "#", "id" => "my_link", "class" => "some_class", "data" => "rah!"
      )
    end

    it "knows about its parents" do
      browser.goto("/ferrum/simple")
      parents = browser.at_css("#nav").native.parents
      expect(parents.map(&:tag_name)).to eq %w[li ul body html]
    end

    context "SVG tests" do
      before do
        browser.goto("/ferrum/svg_test")
      end

      it "gets text from tspan node" do
        expect(browser.at_css("tspan").text).to eq "svg foo"
      end
    end

    context "modals" do
      it "matches on partial strings" do
        browser.goto("/ferrum/with_js")
        expect do
          browser.accept_confirm "[reg.exp] (chara©+er$)" do
            browser.click_link("Open for match")
          end
        end.not_to raise_error
        expect(browser).to have_xpath("//a[@id='open-match' and @confirmed='true']")
      end

      it "matches on regular expressions" do
        browser.goto("/ferrum/with_js")
        expect do
          browser.accept_confirm(/^.t.ext.*\[\w{3}\.\w{3}\]/i) do
            browser.click_link("Open for match")
          end
        end.not_to raise_error
        expect(browser).to have_xpath("//a[@id='open-match' and @confirmed='true']")
      end

      it "works with nested modals" do
        browser.goto("/ferrum/with_js")
        expect do
          browser.dismiss_confirm "Are you really sure?" do
            browser.accept_confirm "Are you sure?" do
              browser.click_link("Open check twice")
            end
          end
        end.not_to raise_error
        expect(browser).to have_xpath("//a[@id='open-twice' and @confirmed='false']")
      end

      it "works with second window" do
        browser.goto

        popup = browser.window_opened_by do
          browser.execute_script <<-JS
            window.open("/ferrum/with_js", "popup")
          JS
        end

        browser.within_window(popup) do
          expect do
            browser.accept_confirm do
              browser.click_link("Open for match")
            end
            expect(browser).to have_xpath("//a[@id='open-match' and @confirmed='true']")
          end.not_to raise_error
        end
        popup.close
      end
    end

    it "can go back when history state has been pushed" do
      browser.goto
      browser.execute_script(%(window.history.pushState({foo: "bar"}, "title", "bar2.html");))
      expect(browser).to have_current_path("/bar2.html")
      expect { browser.go_back }.not_to raise_error
      expect(browser).to have_current_path("/")
    end

    it "can go forward when history state is used" do
      browser.goto
      browser.execute_script(%(window.history.pushState({foo: "bar"}, "title", "bar2.html");))
      expect(browser).to have_current_path("/bar2.html")
      # don't use #go_back here to isolate the test
      browser.execute_script("window.history.go(-1);")
      expect(browser).to have_current_path("/")
      expect { browser.go_forward }.not_to raise_error
      expect(browser).to have_current_path("/bar2.html")
    end

    if Ferrum.mri? && !Ferrum.windows?
      require "pty"
      require "timeout"

      context "with pty" do
        before do
          Tempfile.open(%w[test rb]) do |file|
            file.print(script)
            file.flush

            Timeout.timeout(10) do
              PTY.spawn("bundle exec ruby #{file.path}") do |read, write, pid|
                sleep 0.01 until read.readline.chomp == "Please type enter"
                write.puts
                sleep 0.1 until (status = PTY.check(pid))
                @status = status
              end
            end
          end
        end

        let(:script) do
          <<-RUBY
            require "ferrum"
            browser = Ferrum::Browser.new
            browser.goto("http://example.com")
            puts "Please type enter"
            sleep 1
            browser.current_url
          RUBY
        end

        it do
          expect(@status).to be_success
        end
      end
    end
  end
end
