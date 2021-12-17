# frozen_string_literal: true

module Ferrum
  describe Frame::Runtime do
    context "execute" do
      it "supports executing multiple lines of javascript" do
        browser.execute <<-JS
          var a = 1
          var b = 2
          window.result = a + b
        JS
        expect(browser.evaluate("window.result")).to eq(3)
      end
    end

    context "evaluate" do
      it "can return an element" do
        browser.go_to("/ferrum/type")
        element = browser.evaluate(%(document.getElementById("empty_input")))
        expect(element).to eq(browser.at_css("#empty_input"))
      end

      it "can return structures with elements" do
        browser.go_to("/ferrum/type")
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
    end

    context "evaluate_func" do
      let(:function) do
        <<~JS
          function(c) {
            let a = 1;
            let b = 2;
            return a + b + c;
          }
        JS
      end

      it "supports executing multiple lines of javascript function" do
        expect(browser.evaluate_func(function, 3)).to eq(6)
      end

      it "supports executing multiple lines of javascript function" do
        browser.go_to("/ferrum/index")
        node = browser.at_xpath(".//a")

        function = <<~JS
          function(attributeName) {
            return this.getAttribute(attributeName);
          }
        JS

        expect(browser.evaluate_func(function, "href", on: node)).to eq("js_redirect")
      end
    end

    context "evaluate_async" do
      it "handles evaluate_async value properly" do
        expect(browser.evaluate_async("arguments[0](null)", 5)).to be_nil
        expect(browser.evaluate_async("arguments[0](false)", 5)).to be false
        expect(browser.evaluate_async("arguments[0](true)", 5)).to be true
        expect(browser.evaluate_async(%(arguments[0]({foo: "bar"})), 5)).to eq("foo" => "bar")
      end

      it "will timeout" do
        expect do
          browser.evaluate_async("var callback=arguments[0]; setTimeout(function(){callback(true)}, 4000)", 1)
        end.to raise_error(Ferrum::ScriptTimeoutError)
      end
    end

    it "handles evaluate values properly" do
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

    context "cyclic structure" do
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

        it "objects" do
          expect(browser.evaluate(code % "a")).to eq(CyclicObject.instance)
        end

        it "arrays" do
          expect(browser.evaluate(code % "[a]")).to eq([CyclicObject.instance])
        end
      end

      it "backtracks what it has seen" do
        expect(browser.evaluate("(function() { var a = {}; return [a, a] })()")).to eq([{}, {}])
      end
    end

    context "#add_script_tag" do
      it "adds by url" do
        browser.go_to
        expect do
          browser.evaluate("$('a').first().text()")
        end.to raise_error(Ferrum::JavaScriptError)

        browser.add_script_tag(url: "/ferrum/jquery.min.js")

        expect(browser.evaluate("$('a').first().text()")).to eq("Relative")
      end

      it "adds by path" do
        browser.go_to
        path = "#{Ferrum::Application::FERRUM_PUBLIC}/jquery-1.11.3.min.js"
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

    context "#add_style_tag" do
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

        browser.add_style_tag(url: "/ferrum/add_style_tag.css")

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
end
