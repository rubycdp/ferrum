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

    it "keeps a trailing semicolon that is a statement of its own" do
      browser.execute("const end = Date.now() + ms; while (Date.now() < end);", ms: 10)
      browser.execute("for (window.i = 0; window.i < n; window.i++);", n: 3)
      browser.execute("window.ran = true; if (flag);", flag: false)

      expect(browser.evaluate("[window.i, window.ran]")).to eq([3, true])
      expect(browser.evaluate("a + 1;", a: 1)).to eq(2)
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

    it "converts an object shared by many references once" do
      result = browser.evaluate("() => { let x = { v: 1 }; for (let i = 0; i < 20; i++) x = { l: x, r: x }; return x }")

      expect(result["l"]).to equal(result["r"])
      expect(result.dig(*["l"] * 20)).to eq("v" => 1)
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

  describe "#evaluate with a positional function declaration" do
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
      expect(browser.evaluate(function, 3)).to eq(6)
    end

    it "evaluates a function on a node" do
      browser.go_to("/index")
      node = browser.at_xpath(".//a")

      function = <<~JS
        function(attributeName) {
          return this.getAttribute(attributeName);
        }
      JS

      expect(node.evaluate(function, "href")).to eq("js_redirect")
    end
  end

  describe "on a node of the previous page" do
    it "does not retry if node is not around anymore" do
      stub_const("Ferrum::Frame::Runtime::INTERMITTENT_SLEEP", 5)

      browser.go_to("/table")
      node = browser.at_xpath(".//td")

      browser.go_to("/table")

      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect { node.evaluate("this.textContent") }.to raise_error(Ferrum::NodeNotFoundError)
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

  describe "#evaluate with named arguments" do
    it "names arguments as function parameters" do
      expect(browser.evaluate("a + b", a: 1, b: 2)).to eq(3)
    end

    it "sends each argument separately so nodes stay live" do
      browser.go_to("/index")
      node = browser.at_xpath(".//a")

      expect(browser.evaluate("el.getAttribute(name)", el: node, name: "href")).to eq("js_redirect")
    end

    it "passes positional arguments to a function declaration" do
      expect(browser.evaluate("function(a, b) { return a - b }", 5, 1)).to eq(4)
      expect(browser.evaluate("(a, b) => a * b", 3, 4)).to eq(12)
      expect(browser.evaluate("function({ x }, y = 0) { return x - y }", { x: 5 }, 1)).to eq(4)
    end

    it "raises for named arguments to a function declaration" do
      expect { browser.evaluate("function(a, b) { return a - b }", a: 5, b: 1) }
        .to raise_error(ArgumentError, /A function declaration names its own parameters/)
    end

    it "raises for a node inside an array or hash" do
      browser.go_to("/index")
      link = browser.at_xpath(".//a")

      expect { browser.evaluate("links.length", links: [link]) }
        .to raise_error(ArgumentError, /inside an Array or Hash can't be passed/)
      expect { browser.evaluate("o.links", o: { links: [link] }) }
        .to raise_error(ArgumentError, /inside an Array or Hash can't be passed/)
    end

    it "passes nil, hashes and arrays by value" do
      expect(browser.evaluate("value", value: nil)).to be_nil
      expect(browser.evaluate("value.foo", value: { foo: "bar" })).to eq("bar")
      expect(browser.evaluate("value.length", value: [1, 2, 3])).to eq(3)
    end

    it "raises a SyntaxError for a reserved word as a name" do
      expect { browser.evaluate("1", class: 1) }.to raise_error(Ferrum::JavaScriptError, /SyntaxError/)
    end

    it "passes positional arguments through arguments" do
      expect(browser.evaluate("arguments[0] + arguments[1]", 1, 2)).to eq(3)
    end
  end

  describe "#evaluate with a function declaration" do
    it "evaluates multiple statements" do
      expect(browser.evaluate(<<~JS, 3)).to eq(6)
        function(c) {
          let a = 1;
          let b = 2;
          return a + b + c;
        }
      JS
    end

    it "evaluates a named function declaration" do
      expect(browser.evaluate("function sum(a, b) { return a + b }", 1, 2)).to eq(3)
    end

    it "treats an immediately invoked function as an expression, not a declaration" do
      expect(browser.evaluate(<<~JS)).to eq(3)
        function() {
          let a = 1;
          return a + 2;
        }();
      JS
      expect(browser.evaluate("(function() { return 3 })()")).to eq(3)
      expect(browser.evaluate("(() => 3)()")).to eq(3)
    end

    it "accepts arrow functions with default and destructured parameters" do
      expect(browser.evaluate("(a = 1) => a + 41")).to eq(42)
      expect(browser.evaluate("({ x }) => x", { x: 1 })).to eq(1)
    end

    it "reports errors on the line of the script they're on" do
      expect { browser.evaluate("a +\nmissing", a: 1) }
        .to raise_error(Ferrum::JavaScriptError, /missing is not defined\n\s+at <anonymous>:2:/)
    end

    it "includes the compiled function when a script doesn't compile" do
      expect { browser.evaluate("a +", a: 1) }
        .to raise_error(Ferrum::JavaScriptError, /Unexpected token '\)'\n  in: function\(a\) \{ return \(a \+\n\);/)
    end

    it "includes a thrown value that isn't an Error in the message" do
      expect { browser.evaluate("function() { throw 'boom' }") }
        .to raise_error(Ferrum::JavaScriptError, "Uncaught boom")
    end

    it "ignores trailing comments and semicolons when detecting a declaration" do
      expect(browser.evaluate("function(a) { return a } // adds nothing", 1)).to eq(1)
      expect(browser.evaluate("function(a) { return a };", 1)).to eq(1)
    end

    it "keeps a // inside strings and regular expressions on the last line" do
      expect(browser.evaluate("'http://example.com'")).to eq("http://example.com")
      expect(browser.evaluate("function() { return 'http://example.com' }")).to eq("http://example.com")
      expect(browser.evaluate("'a//b'.replace(/\\/\\//, '-')")).to eq("a-b")
      expect(browser.evaluate("`${'http'}://example.com`")).to eq("http://example.com")
    end

    it "calls a declaration in parentheses" do
      expect(browser.evaluate("(function(v) { return v * 2 })", 21)).to eq(42)
      expect(browser.evaluate("((a, b) => a + b)", 1, 2)).to eq(3)
    end

    it "ignores comments before a declaration" do
      expect(browser.evaluate("// doubles\nfunction(a) { return a * 2 }", 2)).to eq(4)
    end

    it "reads scripts with non-ASCII text" do
      expect(browser.evaluate("/* café */ a + 1 // ü", a: 1)).to eq(2)
      expect(browser.evaluate("// 日本語\nfunction(名前) { return 名前 + '!' }", "é")).to eq("é!")
    end

    it "does not call a function that is merely the result of an expression" do
      expect(browser.evaluate("new Function")).to eq({})
      expect(browser.evaluate("window.setTimeout")).to eq({})
    end
  end

  describe "#evaluate with promises" do
    it "awaits an expression" do
      expect(browser.evaluate("await Promise.resolve(42)")).to eq(42)
    end

    it "awaits a promise returned by a function declaration" do
      expect(browser.evaluate("function() { return new Promise(resolve => setTimeout(() => resolve(42), 100)) }"))
        .to eq(42)
    end

    it "awaits an async function declaration" do
      expect(browser.evaluate("async function(a) { return await Promise.resolve(a) }", 7)).to eq(7)
    end

    it "propagates a rejection" do
      expect { browser.evaluate(%(await Promise.reject(new Error("nope")))) }
        .to raise_error(Ferrum::JavaScriptError, /nope/)
    end

    it "doesn't run the script again when the page navigates while awaiting" do
      browser.go_to("/index")
      browser.execute("sessionStorage.runs = 0")

      expect do
        browser.execute(<<~JS)
          sessionStorage.runs++;
          setTimeout(() => location.reload(), 50);
          await new Promise(() => {});
        JS
      end.to raise_error(Ferrum::NodeNotFoundError)
      expect(browser.evaluate("sessionStorage.runs")).to eq("1")
    end

    it "times out" do
      expect { browser.evaluate("new Promise(() => {})", timeout: 1) }
        .to raise_error(Ferrum::ScriptTimeoutError)
    end

    it "waits past the page timeout when given a longer one" do
      with_timeout(1) do
        expect(browser.evaluate("new Promise(resolve => setTimeout(() => resolve(1), 1500))", timeout: 3)).to eq(1)
      end
    end

    it "raises a script timeout that is also a Ferrum::TimeoutError" do
      expect { browser.evaluate("new Promise(() => {})", timeout: 1) }.to raise_error(Ferrum::TimeoutError)
    end

    it "times out when the page replaces setTimeout" do
      browser.execute("window.setTimeout = () => 0")

      expect { browser.evaluate("new Promise(() => {})", timeout: 1) }.to raise_error(Ferrum::ScriptTimeoutError)
    end

    it "keeps working when the page replaces Promise" do
      browser.execute("window.Promise = undefined")

      expect(browser.evaluate("a + 1", a: 1)).to eq(2)
    end

    it "honours a timeout longer than the page timeout" do
      script = "new Promise(resolve => setTimeout(() => resolve(1), 100))"
      expect(browser.evaluate(script, timeout: browser.timeout + 5)).to eq(1)
    end
  end

  describe "with FERRUM_JS_API=new" do
    around do |example|
      original = ENV.fetch("FERRUM_JS_API", nil)
      ENV["FERRUM_JS_API"] = "new"
      example.run
    ensure
      ENV["FERRUM_JS_API"] = original
    end

    it "awaits a returned promise and raises when it rejects" do
      expect(browser.evaluate("new Promise(resolve => setTimeout(() => resolve(42), 100))")).to eq(42)
      expect { browser.evaluate("Promise.reject(new Error('nope'))") }.to raise_error(Ferrum::JavaScriptError, /nope/)
    end

    it "awaits a returned object with a then method" do
      expect(browser.evaluate("({ then(resolve) { resolve(42) } })")).to eq(42)
    end

    it "makes keywords parameters even when the script reads arguments" do
      expect(browser.evaluate("[foo, arguments[0]]", foo: 1)).to eq([1, 1])
    end

    it "rejects mixing positional and named arguments" do
      expect { browser.evaluate("a", 1, a: 2) }.to raise_error(ArgumentError, /either positionally or by name/)
    end

    it "returns the value of the last of several statements" do
      expect(browser.evaluate("1; 2")).to eq(2)
      expect(browser.evaluate("document.title = 'x'\ndocument.title")).to eq("x")
      expect(browser.evaluate("const a = 1")).to be_nil
    end

    it "runs a script after a leading line break" do
      expect(browser.evaluate("\n  1 + 1\n")).to eq(2)
    end

    it "waits for a promise returned to #execute" do
      browser.execute("return new Promise(resolve => setTimeout(() => { window.done = true; resolve() }, 100))")

      expect(browser.evaluate("window.done")).to be(true)
    end

    it "resolves nodes and dates from Node#evaluate" do
      browser.go_to("/index")
      node = browser.at_xpath(".//a")

      expect(node.evaluate("this.parentNode")).to be_a(Ferrum::Node)
      expect(node.evaluate("new Date(0)")).to be_a(String)
    end

    it "doesn't warn" do
      expect { expect(browser.evaluate("Promise.resolve(1)")).to eq(1) }.not_to output.to_stderr
    end
  end

  describe "#evaluate_handle" do
    it "returns a handle that can be passed back in" do
      browser.go_to("/index")
      handle = browser.evaluate_handle("document.querySelectorAll('a')")

      expect(handle).to be_a(Ferrum::RemoteObject)
      expect(browser.evaluate("nodes.length", nodes: handle)).to eq(browser.css("a").size)
    end

    it "returns nodes as Node" do
      browser.go_to("/index")
      expect(browser.evaluate_handle("document.querySelector('a')")).to be_a(Ferrum::Node)
    end

    it "returns primitives as-is" do
      expect(browser.evaluate_handle("42")).to eq(42)
    end

    it "serializes a handle from an iframe" do
      browser.go_to("/frame_parent")
      frame = browser.at_css("#childFrame").frame

      expect(frame.evaluate_handle("({ title: document.title })").value).to eq("title" => "This is the child frame title")
    end
  end

  describe "Ferrum::Node#evaluate" do
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

    it "calls a named function with #execute" do
      browser.execute("function setup() { window.ran = true }")

      expect(browser.evaluate("window.ran")).to be(true)
    end

    it "runs statements with #execute" do
      node = browser.at_xpath(".//a")
      node.execute("this.dataset.touched = value", value: "yes")

      expect(node.evaluate("this.dataset.touched")).to eq("yes")
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
