# frozen_string_literal: true

describe Ferrum::Frame::Runtime do
  describe "#execute" do
    it "raises when a string is thrown" do
      expect { browser.execute(%(throw "smth")) }.to raise_error(Ferrum::JavaScriptError, "Uncaught smth")
    end

    it "executes multiple lines of javascript" do
      browser.execute <<-JS
        var a = 1
        var b = 2
        window.result = a + b
      JS
      expect(browser.evaluate("window.result")).to eq(3)
    end

    context "with javascript errors" do
      let(:browser) { Ferrum::Browser.new(base_url: base_url, js_errors: true) }

      after { browser.quit }

      it "propagates a Javascript error to a ruby exception", :launch do
        expect do
          browser.execute(%(throw new Error("zomg")))
        end.to raise_error(Ferrum::JavaScriptError) { |e|
          expect(e.message).to include("Error: zomg")
        }
      end

      it "propagates an asynchronous Javascript error on the page to a ruby exception", :launch do
        expect do
          browser.execute "setTimeout(function() { omg }, 0)"
          sleep 0.01
          browser.execute ""
        end.to raise_error(Ferrum::JavaScriptError, /ReferenceError.*omg/)
      end

      it "propagates a synchronous Javascript error on the page to a ruby exception", :launch do
        expect do
          browser.execute "omg"
        end.to raise_error(Ferrum::JavaScriptError, /ReferenceError.*omg/)
      end

      it "does not re-raise a Javascript error if it is rescued", :launch do
        expect do
          browser.execute "setTimeout(function() { omg }, 0)"
          sleep 0.01
          browser.execute ""
        end.to raise_error(Ferrum::JavaScriptError, /ReferenceError.*omg/)

        # should not raise again
        expect(browser.evaluate("1+1")).to eq(2)
      end

      it "propagates a Javascript error during page load to a ruby exception", :launch do
        expect { browser.go_to("/js_error") }.to raise_error(Ferrum::JavaScriptError)
      end

      it "does not propagate a Javascript error to ruby if error raising disabled", :launch do
        browser = Ferrum::Browser.new(base_url: base_url, js_errors: false)
        browser.go_to("/js_error")
        browser.execute "setTimeout(function() { omg }, 0)"
        sleep 0.1
        expect(browser.body).to include("hello")
      ensure
        browser&.quit
      end

      it "does not propagate a Javascript error to ruby if error raising disabled and client restarted", :launch do
        browser = Ferrum::Browser.new(base_url: base_url, js_errors: false)
        browser.restart
        browser.go_to("/js_error")
        browser.execute "setTimeout(function() { omg }, 0)"
        sleep 0.1
        expect(browser.body).to include("hello")
      ensure
        browser&.quit
      end
    end
  end

  describe "#evaluate" do
    it "returns an element" do
      browser.go_to("/type")
      element = browser.evaluate(%(document.getElementById("empty_input")))
      expect(element).to eq(browser.at_css("#empty_input"))
    end

    it "returns deeply nested node" do
      browser.go_to("/deeply_nested")
      node = browser.evaluate(%(document.getElementById("text")))
      expect(node.text).to eq("text")
    end

    it "returns structures with elements" do
      browser.go_to("/type")
      result = browser.evaluate <<~JS
        {
          a: document.getElementById("empty_input"),
          b: { c: document.querySelectorAll("#empty_textarea, #filled_textarea") }
        }
      JS

      expect(result).to eq(
        "a" => browser.at_css("#empty_input"),
        "b" => {
          "c" => browser.css("#empty_textarea, #filled_textarea")
        }
      )
    end

    it "returns nodes of every type" do
      browser.content = <<~HTML
        <!DOCTYPE html>
        <p class="a" id="b">text<!--comment--></p>
        <iframe srcdoc="<b>inner</b>"></iframe>
        <my-element></my-element>
        <svg><circle r="1"/></svg>
        <div id="host"></div>
      HTML
      nodes = browser.evaluate(<<~JS)
        (() => {
          const host = document.getElementById("host");
          host.attachShadow({ mode: "open" });
          const p = document.querySelector("p");
          return [document, document.doctype, p, p.firstChild, p.lastChild, document.querySelector("iframe"),
                  document.querySelector("my-element"), document.querySelector("circle"), host.shadowRoot];
        })()
      JS

      expect(nodes.map(&:tag_name)).to eq(
        %w[#document html p #text #comment iframe my-element circle #document-fragment]
      )
      expect(nodes.map(&:node_type)).to eq([9, 10, 1, 3, 8, 1, 1, 1, 11])
      expect(nodes.map(&:node?)).to eq([false, false, true, false, false, true, true, true, false])
      expect(nodes[5].frame_id).to eq(browser.frames.reject(&:main?).first.id)
      expect(nodes.values_at(0..4, 6..8).map(&:frame_id)).to all(be_nil)
      expect(nodes[2].description).to include("nodeName" => "P", "attributes" => %w[class a id b])
      expect(nodes[8].description).to include("shadowRootType" => "open")
    end

    it "returns values properly" do
      expect(browser.evaluate("null")).to be_nil
      expect(browser.evaluate("false")).to be false
      expect(browser.evaluate("true")).to be true
      expect(browser.evaluate("undefined")).to eq(nil)

      expect(browser.evaluate("3;")).to eq(3)
      expect(browser.evaluate("31337")).to eq(31_337)
      expect(browser.evaluate(%("string"))).to eq("string")
      expect(browser.evaluate(%({foo: "bar"}))).to eq("foo" => "bar")

      expect(browser.evaluate("new Object")).to eq({})
      expect(browser.evaluate("new Date(2012, 0).toDateString()")).to eq("Sun Jan 01 2012")
      expect(browser.evaluate("new Object({a: 1})")).to eq({ "a" => 1 })
      expect(browser.evaluate("new Array")).to eq([])
      expect(browser.evaluate("new Function")).to eq({})

      expect do
        browser.evaluate(%(throw "smth"))
      end.to raise_error(Ferrum::JavaScriptError)
    end

    it "raises when a string is thrown" do
      expect do
        browser.evaluate(%((() => { throw "smth" })()))
      end.to raise_error(Ferrum::JavaScriptError, "Uncaught smth")
    end

    it "raises when an object is thrown" do
      expect do
        browser.evaluate("(() => { throw { code: 1 } })()")
      end.to raise_error(Ferrum::JavaScriptError) { |e| expect(e.class_name).to eq("Object") }
    end

    it "returns an Error object instead of raising" do
      expect(browser.evaluate(%(new Error("smth")))).to eq({})
    end

    it "keeps null and undefined in arrays" do
      expect(browser.evaluate("[1, null, undefined, 3]")).to eq([1, nil, nil, 3])
    end

    it "returns numbers JSON can't represent" do
      expect(browser.evaluate("NaN")).to be_nan
      expect(browser.evaluate("1 / 0")).to eq(Float::INFINITY)
      expect(browser.evaluate("-1 / 0")).to eq(-Float::INFINITY)
      expect(browser.evaluate("-0").to_s).to eq("-0.0")
      expect(browser.evaluate("{ big: 2n ** 64n }")).to eq("big" => 2**64)
    end

    it "returns dates as ISO strings" do
      expect(browser.evaluate("[new Date(Date.UTC(2012, 0))]")).to eq(["2012-01-01T00:00:00.000Z"])
    end

    it "returns values of getters" do
      expect(browser.evaluate("{ get a() { return 1 } }")).to eq("a" => 1)
    end

    it "returns objects without a Ruby equivalent as empty hashes" do
      expect(browser.evaluate("[new Map([[1, 2]]), new Set([1]), /a/, Symbol('a')]")).to eq([{}, {}, {}, nil])
    end

    context "when cyclic structure is returned" do
      let(:cyclic) { Ferrum::CyclicObject.instance }

      context "ignores seen" do
        let(:code) do
          <<~JS
            (function() {
              var a = {};
              var b = {};
              var c = {};
              c.a = a;
              a.a = a;
              a.b = b;
              a.c = c;
              return %s;
            })()
          JS
        end

        it "returns object" do
          expect(browser.evaluate(code % "a")).to eq("a" => cyclic, "b" => {}, "c" => { "a" => cyclic })
        end

        it "returns array" do
          expect(browser.evaluate(code % "[a]")).to eq([{ "a" => cyclic, "b" => {}, "c" => { "a" => cyclic } }])
        end
      end

      it "backtracks what it has seen" do
        expect(browser.evaluate("(function() { var a = {}; return [a, a] })()")).to eq([{}, {}])
      end

      it "returns an array containing itself" do
        expect(browser.evaluate("(function() { var a = [1]; a.push(a); return a })()")).to eq([1, cyclic])
      end

      it "returns window as an empty hash" do
        expect(browser.evaluate("window")).to eq({})
      end

      it "fetches the whole result tree with one command" do
        allow(browser.page).to receive(:command).and_call_original

        result = browser.evaluate(<<~JS)
          Array.from({ length: 50 }, (_, i) => ({ i: i, nested: { j: i * 2 } }))
        JS

        expect(result.size).to eq(50)
        expect(browser.page).to have_received(:command).once
      end
    end
  end

  describe "#evaluate_func" do
    let(:function) do
      <<~JS
        function(c) {
          let a = 1;
          let b = 2;
          return a + b + c;
        }
      JS
    end

    it "evaluates multiple lines of javascript function" do
      expect(browser.evaluate_func(function, 3)).to eq(6)
    end

    it "evaluates a function on a node" do
      browser.go_to("/index")
      node = browser.at_xpath(".//a")

      function = <<~JS
        function(attributeName) {
          return this.getAttribute(attributeName);
        }
      JS

      expect(browser.evaluate_func(function, "href", on: node)).to eq("js_redirect")
    end
  end

  describe "#evaluate_async" do
    it "handles values properly" do
      expect(browser.evaluate_async("arguments[0](null)", 5)).to be_nil
      expect(browser.evaluate_async("arguments[0](false)", 5)).to be false
      expect(browser.evaluate_async("arguments[0](true)", 5)).to be true
      expect(browser.evaluate_async(%(arguments[0]({foo: "bar"})), 5)).to eq("foo" => "bar")
    end

    it "times out" do
      expect do
        browser.evaluate_async("var callback=arguments[0]; setTimeout(function(){callback(true)}, 4000)", 1)
      end.to raise_error(Ferrum::ScriptTimeoutError)
    end

    it "raises when a string is thrown" do
      expect do
        browser.evaluate_async(%(throw "smth"), 5)
      end.to raise_error(Ferrum::JavaScriptError, "Uncaught (in promise) smth")
    end
  end

  describe "#evaluate_on" do
    it "raises when a string is thrown" do
      browser.go_to("/table")
      node = browser.at_xpath(".//td")

      expect do
        browser.evaluate_on(node: node, expression: %((() => { throw "smth" })()))
      end.to raise_error(Ferrum::JavaScriptError, "Uncaught smth")
    end

    it "does not retry if node is not around anymore" do
      stub_const("Ferrum::Frame::Runtime::INTERMITTENT_SLEEP", 5)

      browser.go_to("/table")
      node = browser.at_xpath(".//td")

      browser.go_to("/table")

      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect { browser.evaluate_on(node: node, expression: "this.textContent") }.to raise_error(Ferrum::NodeNotFoundError)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

      expect(elapsed).to be < Ferrum::Frame::Runtime::INTERMITTENT_SLEEP
    end

    it "raises NodeNotFoundError for a node resolved on the previous page" do
      browser.go_to("/table")
      node = browser.at_xpath(".//td")
      object_id = browser.page.command("DOM.resolveNode", nodeId: node.node_id).dig("object", "objectId")

      browser.go_to("/table")

      expect do
        browser.evaluate("arguments[0].textContent", { "objectId" => object_id })
      end.to raise_error(Ferrum::NodeNotFoundError, /same JavaScript world/)
    end
  end

  describe "#add_script_tag" do
    it "adds by url" do
      browser.go_to
      expect do
        browser.evaluate("$('a').first().text()")
      end.to raise_error(Ferrum::JavaScriptError)

      browser.add_script_tag(url: "/jquery.min.js")

      expect(browser.evaluate("$('a').first().text()")).to eq("Relative")
    end

    it "adds by path" do
      browser.go_to
      path = "#{Ferrum::Application::FERRUM_PUBLIC}/jquery-3.7.1.min.js"
      expect do
        browser.evaluate("$('a').first().text()")
      end.to raise_error(Ferrum::JavaScriptError)

      browser.add_script_tag(path: path)

      expect(browser.evaluate("$('a').first().text()")).to eq("Relative")
    end

    it "adds by content" do
      browser.go_to

      browser.add_script_tag(content: "function yay() { return 'yay!'; }")

      expect(browser.evaluate("yay()")).to eq("yay!")
    end
  end

  describe "#add_style_tag" do
    let(:font_size) do
      <<~JS
        window
          .getComputedStyle(document.querySelector('a'))
          .getPropertyValue('font-size')
      JS
    end

    it "adds by url" do
      browser.go_to
      expect(browser.evaluate(font_size)).to eq("16px")

      browser.add_style_tag(url: "/add_style_tag.css")

      expect(browser.evaluate(font_size)).to eq("50px")
    end

    it "adds by path" do
      browser.go_to
      path = "#{Ferrum::Application::FERRUM_PUBLIC}/add_style_tag.css"
      expect(browser.evaluate(font_size)).to eq("16px")

      browser.add_style_tag(path: path)

      expect(browser.evaluate(font_size)).to eq("50px")
    end

    it "adds by content" do
      browser.go_to

      browser.add_style_tag(content: "a { font-size: 20px; }")

      expect(browser.evaluate(font_size)).to eq("20px")
    end
  end
end
