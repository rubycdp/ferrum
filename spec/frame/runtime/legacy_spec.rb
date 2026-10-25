# frozen_string_literal: true

describe Ferrum::Frame::Runtime::Legacy do
  around do |example|
    Ferrum::Utils::Deprecate.reset!
    example.run
    Ferrum::Utils::Deprecate.reset!
  end

  def evaluate_warning(message, &block)
    result = nil
    expect { result = block.call }.to output(message).to_stderr
    result
  end

  describe "calls that keep working unchanged" do
    it "doesn't warn about plain expressions and positional arguments" do
      browser.go_to("/index")

      expect do
        browser.evaluate("1 + 1")
        browser.evaluate("arguments[0] + arguments[1]", 1, 2)
        browser.evaluate("arguments[0].a", { a: 1 })
        browser.execute("window.x = arguments[0]", 1)
        browser.at_xpath(".//a").evaluate("this.id")
        browser.evaluate("[1,\n 2];\n")
        browser.evaluate("(() => { const a = 1; return a })()")
      end.not_to output.to_stderr
    end

    it "returns an object with a then method as it is" do
      expect do
        expect(browser.evaluate("({ then() {}, a: 1 })")).to eq("then" => {}, "a" => 1)
        expect(browser.execute("return Object.create({ then() {} })")).to be(true)
      end.not_to output.to_stderr
    end
  end

  describe "calls that change in 0.21" do
    it "passes keyword arguments as one object to a script reading arguments" do
      result = evaluate_warning(/become named parameters.*\n  script: arguments\[0\]\.foo\n  called from #{__FILE__}/) do
        browser.evaluate("arguments[0].foo", foo: "bar")
      end

      expect(result).to eq("bar")
    end

    it "passes reserved keywords along with the rest" do
      result = evaluate_warning(/become named parameters/) { browser.evaluate("arguments[0]", timeout: 2) }

      expect(result).to eq("timeout" => 2)
    end

    it "appends keyword arguments mixed with positional ones" do
      result = evaluate_warning(/Mixing positional and keyword arguments will raise ArgumentError/) do
        browser.evaluate("[arguments[0], arguments[1]]", 1, foo: 2)
      end

      expect(result).to eq([1, { "foo" => 2 }])
    end

    it "returns the first of several statements" do
      result = evaluate_warning(/more than one statement, and today only the first one runs/) { browser.evaluate("1; 2") }

      expect(result).to eq(1)
    end

    it "doesn't run a script after a leading line break" do
      result = evaluate_warning(/This script never runs/) { browser.evaluate("\n  window.ran = true\n") }

      expect(result).to be_nil
      expect(browser.evaluate("window.ran")).to be_nil
    end

    it "returns a promise as an empty object" do
      result = evaluate_warning(/returns a promise, which comes back as \{\} today/) do
        browser.evaluate("Promise.resolve(42)")
      end

      expect(result).to eq({})
    end

    it "doesn't wait for a promise #execute returns" do
      result = evaluate_warning(/returns a promise, which #execute will wait for/) do
        browser.execute("return new Promise(() => {})")
      end

      expect(result).to be(true)
    end

    it "returns a DOM node from Node#evaluate as an empty object" do
      browser.go_to("/index")
      node = browser.at_xpath(".//a")

      result = evaluate_warning(/returns a DOM node as \{\} today/) { node.evaluate("this.parentNode") }

      expect(result).to eq({})
    end

    it "returns a Date from Node#evaluate as an empty object" do
      browser.go_to("/index")
      node = browser.at_xpath(".//a")

      result = evaluate_warning(/returns a Date as \{\} today/) { node.evaluate("new Date(0)") }

      expect(result).to eq({})
    end

    it "returns DOM nodes in an array from Node#evaluate as empty objects" do
      browser.go_to("/index")
      node = browser.at_xpath(".//a")

      result = evaluate_warning(/returns DOM nodes in an array as \{\} today/) { node.evaluate("[this]") }

      expect(result).to eq([{}])
    end
  end

  describe "methods removed in 0.21" do
    it "keeps #evaluate_async" do
      result = evaluate_warning(/#evaluate_async will be removed in Ferrum 0.21/) do
        browser.evaluate_async("arguments[0](1)", 1)
      end

      expect(result).to eq(1)
    end

    it "handles values with #evaluate_async" do
      ENV["FERRUM_DEPRECATION_WARNINGS"] = "0"

      expect(browser.evaluate_async("arguments[0](null)", 5)).to be_nil
      expect(browser.evaluate_async("arguments[0](false)", 5)).to be false
      expect(browser.evaluate_async("arguments[0](true)", 5)).to be true
      expect(browser.evaluate_async(%(arguments[0]({foo: "bar"})), 5)).to eq("foo" => "bar")
    ensure
      ENV.delete("FERRUM_DEPRECATION_WARNINGS")
    end

    it "times out with #evaluate_async" do
      ENV["FERRUM_DEPRECATION_WARNINGS"] = "0"

      expect do
        browser.evaluate_async("var callback=arguments[0]; setTimeout(function(){callback(true)}, 4000)", 1)
      end.to raise_error(Ferrum::ScriptTimeoutError)
    ensure
      ENV.delete("FERRUM_DEPRECATION_WARNINGS")
    end

    it "keeps #evaluate_func" do
      result = evaluate_warning(/#evaluate_func will be removed in Ferrum 0.21/) do
        browser.evaluate_func("function(a) { return a }", 1)
      end

      expect(result).to eq(1)
    end

    it "keeps #evaluate_on" do
      browser.go_to("/index")
      node = browser.at_xpath(".//a")

      result = evaluate_warning(/#evaluate_on will be removed in Ferrum 0.21/) do
        browser.evaluate_on(node: node, expression: "this.tagName")
      end

      expect(result).to eq("A")
    end

    it "points #evaluate_on with wait: at #wait_for_navigation!" do
      browser.go_to("/index")
      node = browser.at_xpath(".//a")

      evaluate_warning(/Use page\.wait_for_navigation!\(0\.1\) \{ node\.evaluate\("this\.value"\) \} instead/) do
        browser.evaluate_on(node: node, expression: "this.tagName", wait: 0.1)
      end
    end

    it "raises when a string is thrown in #evaluate_async or #evaluate_on" do
      ENV["FERRUM_DEPRECATION_WARNINGS"] = "0"
      browser.go_to("/table")
      node = browser.at_xpath(".//td")

      expect do
        browser.evaluate_async(%(throw "smth"), 5)
      end.to raise_error(Ferrum::JavaScriptError, "Uncaught (in promise) smth")
      expect do
        browser.evaluate_on(node: node, expression: %((() => { throw "smth" })()))
      end.to raise_error(Ferrum::JavaScriptError, "Uncaught smth")
    ensure
      ENV.delete("FERRUM_DEPRECATION_WARNINGS")
    end
  end

  describe "warnings" do
    it "warns once per call site" do
      stderr = StringIO.new
      original = $stderr
      $stderr = stderr
      begin
        3.times { browser.evaluate("1; 2") }
      ensure
        $stderr = original
      end

      expect(stderr.string.scan("DEPRECATION").size).to eq(1)
    end

    it "raises when FERRUM_DEPRECATION_WARNINGS=raise" do
      ENV["FERRUM_DEPRECATION_WARNINGS"] = "raise"

      expect { browser.evaluate("1; 2") }.to raise_error(Ferrum::Error, /DEPRECATION/)
    ensure
      ENV.delete("FERRUM_DEPRECATION_WARNINGS")
    end

    it "stays quiet when FERRUM_DEPRECATION_WARNINGS=0" do
      ENV["FERRUM_DEPRECATION_WARNINGS"] = "0"

      expect { browser.evaluate("1; 2") }.not_to output.to_stderr
    ensure
      ENV.delete("FERRUM_DEPRECATION_WARNINGS")
    end
  end
end
