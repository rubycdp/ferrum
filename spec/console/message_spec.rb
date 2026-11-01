# frozen_string_literal: true

describe Ferrum::Console::Message do
  def log(script)
    page.go_to
    page.execute(script)
    wait_for { page.console.size }.to eq(1)
    page.console.last
  end

  def throw_error
    log(%(setTimeout(function thrower() { throw new Error("boom") })))
  end

  def fail_to_load_image
    log(%(document.body.appendChild(document.createElement("img")).src = "/unexist.png"))
  end

  def log_nested
    log(<<~JS)
      function inner() { console.log("nested") }
      function outer() { inner() }
      outer()
    JS
  end

  describe "#text" do
    it "joins console arguments with spaces" do
      expect(log(%(console.log("a", 1, true))).text).to eq("a 1 true")
    end

    it "renders objects and arrays as JSON" do
      expect(log(%(console.log({ a: 1 }, [1, "b"]))).text).to eq(%({"a":1} [1,"b"]))
    end

    it "returns the exception text for an uncaught exception" do
      expect(throw_error.text).to start_with("Uncaught Error: boom")
    end

    it "returns the entry text for a browser log entry" do
      expect(fail_to_load_image.text).to include("404")
    end
  end

  describe "#args" do
    it "returns special numbers as floats" do
      expect(log(%(console.log(Infinity, -Infinity, -0))).args).to eq([Float::INFINITY, -Float::INFINITY, -0.0])
    end

    it "converts the properties of an object preview" do
      message = log(%(console.log({ n: 1.5, t: true, f: false }, { u: undefined, z: null, big: 10n, inf: Infinity })))

      expect(message.args).to eq(
        [{ "n" => 1.5, "t" => true, "f" => false }, { "u" => nil, "z" => nil, "big" => 10, "inf" => Float::INFINITY }]
      )
    end

    it "returns the description of a DOM node" do
      expect(log(%(console.log(document.body))).args).to eq(["body"])
    end

    it "returns an empty array for an uncaught exception" do
      expect(throw_error.args).to eq([])
    end
  end

  describe "#stack_trace" do
    it "lists the frames innermost first" do
      expect(log_nested.stack_trace.map(&:function_name).first(2)).to eq(%w[inner outer])
    end

    it "returns the frame of the thrown exception" do
      expect(throw_error.stack_trace.first.function_name).to eq("thrower")
    end
  end

  describe "#location" do
    it "returns the innermost frame" do
      message = log_nested

      expect(message.location.function_name).to eq("inner")
      expect(message.location.line).to eq(1)
      expect(message.location.column).to be_positive
    end

    it "returns the url of a resource that failed to load" do
      expect(fail_to_load_image.location.to_s).to eq(base_url("/unexist.png"))
    end
  end

  describe "#severity" do
    it "returns :error for console.error" do
      expect(log(%(console.error("x"))).severity).to eq(:error)
    end

    it "returns :error for a failed console.assert" do
      expect(log(%(console.assert(false, "x"))).severity).to eq(:error)
    end

    it "returns :warn for console.warn" do
      expect(log(%(console.warn("x"))).severity).to eq(:warn)
    end

    it "returns :debug for console.debug" do
      expect(log(%(console.debug("x"))).severity).to eq(:debug)
    end

    it "returns :info for console.log" do
      expect(log(%(console.log("x"))).severity).to eq(:info)
    end
  end

  describe "#error?" do
    it "returns true for console.error" do
      expect(log(%(console.error("x")))).to be_error
    end

    it "returns true for an uncaught exception" do
      expect(throw_error).to be_error
    end

    it "returns false for console.warn" do
      expect(log(%(console.warn("x")))).not_to be_error
    end
  end

  describe "#warning?" do
    it "returns true for console.warn" do
      expect(log(%(console.warn("x")))).to be_warning
    end

    it "returns false for console.error" do
      expect(log(%(console.error("x")))).not_to be_warning
    end
  end

  describe "#match?" do
    it "matches a regexp against the text" do
      expect(log(%(console.log("Hello world")))).to be_match(/hello W/i)
    end

    it "checks whether the text includes a string" do
      expect(log(%(console.log("Hello world")))).to be_match("lo wo")
    end

    it "treats a string pattern literally" do
      expect(log(%(console.log("Hello world")))).not_to be_match("Hello.world")
    end
  end

  describe "#to_s" do
    it "prints the type and text followed by a line per frame" do
      message = log_nested

      expect(message.to_s.lines.first(3)).to match(
        ["[log] nested\n", /\A    at inner \(.*:1:\d+\)\n\z/, /\A    at outer \(.*:2:\d+\)\n\z/]
      )
    end
  end
end
