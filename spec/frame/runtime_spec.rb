# frozen_string_literal: true

describe Ferrum::Frame::Runtime do
  describe "#execute" do
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

      it "propagates a Javascript error to a ruby exception" do
        expect do
          browser.execute(%(throw new Error("zomg")))
        end.to raise_error(Ferrum::JavaScriptError) { |e|
          expect(e.message).to include("Error: zomg")
        }
      end

      it "propagates an asynchronous Javascript error on the page to a ruby exception" do
        expect do
          browser.execute "setTimeout(function() { omg }, 0)"
          sleep 0.01
          browser.execute ""
        end.to raise_error(Ferrum::JavaScriptError, /ReferenceError.*omg/)
      end

      it "propagates a synchronous Javascript error on the page to a ruby exception" do
        expect do
          browser.execute "omg"
        end.to raise_error(Ferrum::JavaScriptError, /ReferenceError.*omg/)
      end

      it "does not re-raise a Javascript error if it is rescued" do
        expect do
          browser.execute "setTimeout(function() { omg }, 0)"
          sleep 0.01
          browser.execute ""
        end.to raise_error(Ferrum::JavaScriptError, /ReferenceError.*omg/)

        # should not raise again
        expect(browser.evaluate("1+1")).to eq(2)
      end

      it "propagates a Javascript error during page load to a ruby exception" do
        expect { browser.go_to("/js_error") }.to raise_error(Ferrum::JavaScriptError)
      end

      it "does not propagate a Javascript error to ruby if error raising disabled" do
        browser = Ferrum::Browser.new(base_url: base_url, js_errors: false)
        browser.go_to("/js_error")
        browser.execute "setTimeout(function() { omg }, 0)"
        sleep 0.1
        expect(browser.body).to include("hello")
      ensure
        browser&.quit
      end

      it "does not propagate a Javascript error to ruby if error raising disabled and client restarted" do
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

    context "when cyclic structure is returned" do
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
          expect(browser.evaluate(code % "a")).to eq(Ferrum::CyclicObject.instance)
        end

        it "returns array" do
          expect(browser.evaluate(code % "[a]")).to eq([Ferrum::CyclicObject.instance])
        end
      end

      it "backtracks what it has seen" do
        expect(browser.evaluate("(function() { var a = {}; return [a, a] })()")).to eq([{}, {}])
      end

      it "only checks for a cycle once for the whole result tree, not once per nested object" do
        frame = browser.main_frame
        original_cyclic = frame.method(:cyclic?)
        calls = 0
        allow(frame).to receive(:cyclic?) do |*args|
          calls += 1
          original_cyclic.call(*args)
        end

        result = browser.evaluate(<<~JS)
          Array.from({ length: 50 }, (_, i) => ({ i: i, nested: { j: i * 2 } }))
        JS

        expect(result.size).to eq(50)
        expect(calls).to eq(1)
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
  end

  describe "#evaluate_on" do
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

    it "binds by name when the script declares its own parameters" do
      expect(browser.evaluate("function(a, b) { return a - b }", b: 1, a: 5)).to eq(4)
    end

    it "falls back to insertion order when the names don't line up" do
      expect(browser.evaluate("function(x, y) { return x - y }", a: 5, b: 1)).to eq(4)
    end

    it "accepts arrow functions" do
      expect(browser.evaluate("(a, b) => a * b", a: 3, b: 4)).to eq(12)
      expect(browser.evaluate("a => a * 2", a: 21)).to eq(42)
    end

    it "passes nil, hashes and arrays by value" do
      expect(browser.evaluate("value", value: nil)).to be_nil
      expect(browser.evaluate("value.foo", value: { foo: "bar" })).to eq("bar")
      expect(browser.evaluate("value.length", value: [1, 2, 3])).to eq(3)
    end

    it "accepts reserved names through args:" do
      expect(browser.evaluate("timeout * 2", args: { timeout: 21 })).to eq(42)
    end

    it "rejects names that aren't valid JavaScript identifiers" do
      expect { browser.evaluate("a", args: { "not-an-identifier": 1 }) }
        .to raise_error(ArgumentError, /not a valid JavaScript parameter name/)
    end

    it "rejects mixing positional and named arguments" do
      expect { browser.evaluate("a", 1, a: 2) }
        .to raise_error(ArgumentError, /either positionally or by name/)
    end

    it "still accepts deprecated positional arguments" do
      expect(browser.evaluate("arguments[0] + arguments[1]", 1, 2)).to eq(3)
    end
  end

  describe "#evaluate with a function declaration" do
    it "evaluates multiple statements" do
      expect(browser.evaluate(<<~JS, c: 3)).to eq(6)
        function(c) {
          let a = 1;
          let b = 2;
          return a + b + c;
        }
      JS
    end

    it "evaluates a named function declaration" do
      expect(browser.evaluate("function sum(a, b) { return a + b }", a: 1, b: 2)).to eq(3)
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

    it "ignores trailing comments and semicolons when detecting a declaration" do
      expect(browser.evaluate("function(a) { return a } // adds nothing", a: 1)).to eq(1)
      expect(browser.evaluate("function(a) { return a };", a: 1)).to eq(1)
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

    it "awaits a returned promise" do
      expect(browser.evaluate("new Promise(resolve => setTimeout(() => resolve(42), 100))")).to eq(42)
    end

    it "awaits an async function declaration" do
      expect(browser.evaluate("async function(a) { return await Promise.resolve(a) }", a: 7)).to eq(7)
    end

    it "propagates a rejection" do
      expect { browser.evaluate(%(await Promise.reject(new Error("nope")))) }
        .to raise_error(Ferrum::JavaScriptError, /nope/)
    end

    it "times out" do
      expect { browser.evaluate("new Promise(() => {})", timeout: 1) }
        .to raise_error(Ferrum::ScriptTimeoutError)
    end

    it "honours a timeout longer than the page timeout" do
      script = "new Promise(resolve => setTimeout(() => resolve(1), 100))"
      expect(browser.evaluate(script, timeout: browser.timeout + 5)).to eq(1)
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
  end

  describe "Ferrum::Node#evaluate" do
    before { browser.go_to("/index") }

    it "binds this to the node" do
      expect(browser.at_xpath(".//a").evaluate("this.getAttribute('href')")).to eq("js_redirect")
    end

    it "accepts named arguments" do
      expect(browser.at_xpath(".//a").evaluate("this.getAttribute(name)", name: "href")).to eq("js_redirect")
    end

    it "resolves nodes instead of returning them by value" do
      expect(browser.at_xpath(".//a").evaluate("this.parentNode")).to be_a(Ferrum::Node)
    end

    it "runs statements with #execute" do
      node = browser.at_xpath(".//a")
      node.execute("this.dataset.touched = value", value: "yes")

      expect(node.evaluate("this.dataset.touched")).to eq("yes")
    end
  end

  describe "deprecations" do
    around do |example|
      Ferrum::Utils::Deprecate.reset!
      example.run
      Ferrum::Utils::Deprecate.reset!
    end

    it "warns about #evaluate_async" do
      expect { browser.evaluate_async("arguments[0](1)", 1) }
        .to output(/DEPRECATION: .*#evaluate_async/).to_stderr
    end

    it "warns about #evaluate_func" do
      expect { browser.evaluate_func("function(a) { return a }", 1) }
        .to output(/DEPRECATION: .*#evaluate_func/).to_stderr
    end

    it "warns about #evaluate_on" do
      browser.go_to("/index")
      node = browser.at_xpath(".//a")

      expect { browser.evaluate_on(node: node, expression: "this.tagName") }
        .to output(/DEPRECATION: .*#evaluate_on/).to_stderr
    end

    it "warns about positional arguments" do
      expect { browser.evaluate("arguments[0]", 1) }
        .to output(/DEPRECATION: .*#evaluate with positional arguments/).to_stderr
    end

    it "warns about positional arguments to #execute" do
      expect { browser.execute("window.__x = arguments[0]", 1) }
        .to output(/DEPRECATION: .*#execute with positional arguments/).to_stderr
    end

    it "warns once per call site" do
      original = $stderr
      $stderr = StringIO.new
      3.times { browser.evaluate("arguments[0]", 1) }
      output = $stderr.string
      $stderr = original

      expect(output.scan("DEPRECATION").size).to eq(1)
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
