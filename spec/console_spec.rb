# frozen_string_literal: true

describe Ferrum::Console do
  let(:console) { page.console }

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

  it "forgets messages on clear" do
    page.go_to("/console_log")
    wait_for { console.size }.to eq(1)

    console.clear
    expect(console).to be_empty

    page.execute(%(console.log("again")))
    wait_for { console.map(&:text) }.to eq(["again"])
  end

  it "is reachable through the browser" do
    browser.go_to("/console_log")

    wait_for { browser.console.map(&:text) }.to eq(["Hello world"])
  end

  describe "page.on(:console)" do
    it "yields new messages" do
      messages = []
      page.on(:console) { |message| messages << message.text }

      page.go_to("/console_log")
      page.execute(%(console.warn("later")))

      wait_for { messages }.to eq(["Hello world", "later"])
    end

    it "stops yielding after page.off(:console)" do
      messages = []
      id = page.on(:console) { |message| messages << message.text }

      page.go_to
      page.execute(%(console.log("first")))
      wait_for { messages }.to eq(["first"])

      page.off(:console, id)
      page.execute(%(console.log("second")))
      wait_for { console.size }.to eq(2)

      expect(messages).to eq(["first"])
    end
  end
end
