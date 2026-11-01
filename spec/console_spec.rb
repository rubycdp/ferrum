# frozen_string_literal: true

describe Ferrum::Console do
  let(:console) { page.console }

  describe "#each" do
    it "collects console API calls" do
      page.go_to("/console_log")

      wait_for { console.size }.to eq(1)
      message = console.first
      expect(message.type).to eq(:log)
      expect(message.source).to eq(:console_api)
      expect(message.text).to eq("Hello world")
      expect(message.severity).to eq(:info)
      expect(message.timestamp).to be_within(60).of(Time.now)
      expect(message.location.url).to end_with("/console_log")
      expect(message.location.function_name).to eq("window.onload")
      expect(message.to_s).to start_with("[log] Hello world\n    at window.onload (")
    end

    it "converts arguments to Ruby values" do
      page.go_to
      page.execute(<<~JS)
        console.log("text", 1, 1.5, true, null, undefined, NaN, 10n,
                    { a: 1, b: "x", c: [1, 2] }, [1, "a", null], () => 1)
      JS

      wait_for { console.size }.to eq(1)
      expect(console.first.args).to match(
        ["text", 1, 1.5, true, nil, nil, be_nan, 10, { "a" => 1, "b" => "x", "c" => "Array(2)" }, [1, "a", nil], "() => 1"]
      )
      expect(console.first.text).to eq(
        %(text 1 1.5 true null undefined NaN 10n {"a":1,"b":"x","c":"Array(2)"} [1,"a",null] () => 1)
      )
    end

    it "tells errors and warnings apart" do
      page.go_to
      page.execute(<<~JS)
        console.error("bad")
        console.warn("careful")
        console.info("fine")
      JS

      wait_for { console.size }.to eq(3)
      expect(console.select(&:error?).map(&:text)).to eq(["bad"])
      expect(console.select(&:warning?).map(&:text)).to eq(["careful"])
      expect(console.map(&:type)).to eq(%i[error warning info])
    end

    it "collects uncaught exceptions" do
      page.go_to
      page.execute(%(setTimeout(() => { throw new Error("boom") })))

      wait_for { console.size }.to eq(1)
      message = console.first
      expect(message.source).to eq(:exception)
      expect(message).to be_error
      expect(message.text).to start_with("Uncaught Error: boom")
    end

    it "collects browser log entries" do
      page.go_to
      page.execute(%(document.body.appendChild(document.createElement("img")).src = "/unexist.png"))

      wait_for { console.size }.to eq(1)
      message = console.first
      expect(message.source).to eq(:network)
      expect(message).to be_error
      expect(message).to be_match("404")
      expect(message.location.url).to end_with("/unexist.png")
    end

    it "keeps only the most recent messages" do
      page.go_to
      page.execute("for (let i = 0; i < #{described_class::LIMIT + 5}; i++) console.log(i)")

      wait_for { console.last&.text }.to eq((described_class::LIMIT + 4).to_s)
      expect(console.size).to eq(described_class::LIMIT)
      expect(console.first.text).to eq("5")
    end

    it "returns an enumerator when no block is given" do
      page.go_to
      page.execute(%(console.log("a"); console.log("b")))

      wait_for { console.size }.to eq(2)
      enumerator = console.each
      expect(enumerator.size).to eq(2)
      expect(enumerator.map(&:text)).to eq(%w[a b])
    end
  end

  describe "#to_a" do
    it "returns the collected messages oldest first" do
      page.go_to
      page.execute(%(console.log("a"); console.log("b")))

      wait_for { console.to_a.map(&:text) }.to eq(%w[a b])
    end

    it "returns a copy that doesn't change the console" do
      page.go_to("/console_log")
      wait_for { console.size }.to eq(1)

      console.to_a.clear

      expect(console.size).to eq(1)
    end
  end

  describe "#last" do
    it "returns the most recent message" do
      page.go_to
      page.execute(%(console.log("a"); console.log("b")))

      wait_for { console.size }.to eq(2)
      expect(console.last.text).to eq("b")
    end

    it "returns nil when no message was collected" do
      page.go_to

      expect(console.last).to be_nil
    end
  end

  describe "#size" do
    it "returns the number of collected messages" do
      page.go_to
      expect(console.size).to eq(0)

      page.execute(%(console.log("a"); console.log("b")))

      wait_for { console.size }.to eq(2)
    end
  end

  describe "#empty?" do
    it "returns true when no message was collected" do
      page.go_to

      expect(console).to be_empty
    end

    it "returns false once a message is collected" do
      page.go_to("/console_log")

      wait_for { console.empty? }.to be(false)
    end
  end

  describe "#clear" do
    it "forgets the collected messages" do
      page.go_to("/console_log")
      wait_for { console.size }.to eq(1)

      console.clear
      expect(console).to be_empty

      page.execute(%(console.log("again")))
      wait_for { console.map(&:text) }.to eq(["again"])
    end
  end

  describe "#on" do
    it "calls the block for every new message" do
      texts = Concurrent::Array.new
      console.on { |message| texts << message.text }

      page.go_to
      page.execute(%(console.log("a"); console.log("b")))

      wait_for { texts }.to eq(%w[a b])
    end

    it "returns a distinct id for every listener" do
      first = console.on { nil }
      second = console.on { nil }

      expect(first).not_to eq(second)
    end
  end

  describe "#off" do
    it "stops calling the removed listener" do
      removed = Concurrent::Array.new
      kept = Concurrent::Array.new
      id = console.on { |message| removed << message.text }
      console.on { |message| kept << message.text }

      console.off(id)
      page.go_to
      page.execute(%(console.log("a")))

      wait_for { kept }.to eq(["a"])
      expect(removed).to be_empty
    end
  end
end
