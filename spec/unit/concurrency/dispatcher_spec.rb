# frozen_string_literal: true

describe Ferrum::Concurrency::Dispatcher do
  subject(:dispatcher) { described_class.new }

  after { dispatcher.close }

  describe "#publish" do
    it "delivers the payload to the callbacks of the key" do
      called = Queue.new
      dispatcher.on("greeting") { |payload| called << payload }

      dispatcher.publish("greeting", "hello")

      expect(called.pop).to eq("hello")
    end

    it "passes only the payload to every callback of the key" do
      called = Queue.new
      dispatcher.on("greeting", &->(payload) { called << [:first, payload] })
      dispatcher.on("greeting", &->(payload) { called << [:second, payload] })

      dispatcher.publish("greeting", "hello")

      expect([called.pop, called.pop]).to eq([[:first, "hello"], [:second, "hello"]])
    end

    it "delivers in order within a lane" do
      called = Queue.new
      dispatcher.on("count") { |payload| called << payload }

      3.times { |i| dispatcher.publish("count", i) }

      expect(Array.new(3) { called.pop }).to eq([0, 1, 2])
    end

    it "delivers on a lane while another one is blocked" do
      release = Queue.new
      called = Queue.new
      dispatcher.on("slow") { release.pop }
      dispatcher.on("fast") { called << :fast }

      dispatcher.publish("slow", nil, lane: :regular)
      dispatcher.publish("fast", nil, lane: :priority)

      expect(called.pop).to eq(:fast)
      release << :go
    end

    it "keeps delivering after a callback raises" do
      called = Queue.new
      errors = []
      dispatcher = described_class.new(on_error: ->(key, e) { errors << [key, e.message] })
      dispatcher.on("boom") { raise "failed" }
      dispatcher.on("boom") { called << :second }

      dispatcher.publish("boom", nil)

      expect(called.pop).to eq(:second)
      expect(errors).to eq([%w[boom failed]])
      dispatcher.close
    end

    it "raises for an unknown lane" do
      expect { dispatcher.publish("greeting", "hello", lane: :urgent) }.to raise_error(KeyError)
    end
  end

  describe "#on" do
    it "returns a different id for every callback" do
      ids = Array.new(3) { dispatcher.on("greeting") { nil } }

      expect(ids.uniq.size).to eq(3)
    end
  end

  describe "#off" do
    it "removes the callback with the given id after an earlier one is gone" do
      first = dispatcher.on("greeting") { nil }
      second = dispatcher.on("greeting") { nil }

      dispatcher.off("greeting", first)
      dispatcher.off("greeting", second)

      expect(dispatcher).not_to be_subscribed("greeting")
    end

    it "keeps the other callbacks" do
      called = Queue.new
      first = dispatcher.on("greeting") { called << :first }
      dispatcher.on("greeting") { called << :second }

      dispatcher.off("greeting", first)
      dispatcher.publish("greeting", nil)

      expect(called.pop).to eq(:second)
    end

    it "does nothing for a key nobody subscribed to" do
      expect(dispatcher.off("greeting", 1)).to be(true)
    end
  end

  describe "#clear" do
    it "removes the callbacks of the keys the block selects" do
      dispatcher.on("a:1") { nil }
      dispatcher.on("b:2") { nil }

      dispatcher.clear { |k| k.end_with?("1") }

      expect(dispatcher).not_to be_subscribed("a:1")
      expect(dispatcher).to be_subscribed("b:2")
    end
  end
end
