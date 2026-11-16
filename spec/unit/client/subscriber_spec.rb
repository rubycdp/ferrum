# frozen_string_literal: true

describe Ferrum::Client::Subscriber do
  subject(:subscriber) { described_class.new }

  after { subscriber.close }

  describe "#on" do
    it "returns a different id for every callback" do
      ids = Array.new(3) { subscriber.on("Page.loadEventFired") { nil } }

      expect(ids.uniq.size).to eq(3)
    end
  end

  describe "#off" do
    it "removes the callback with the given id after an earlier one is gone" do
      first = subscriber.on("Page.loadEventFired") { nil }
      second = subscriber.on("Page.loadEventFired") { nil }

      subscriber.off("Page.loadEventFired", first)
      subscriber.off("Page.loadEventFired", second)

      expect(subscriber).not_to be_subscribed("Page.loadEventFired")
    end

    it "keeps the other callbacks" do
      called = Queue.new
      first = subscriber.on("Page.loadEventFired") { called << :first }
      subscriber.on("Page.loadEventFired") { called << :second }

      subscriber.off("Page.loadEventFired", first)
      subscriber << { "method" => "Page.loadEventFired", "params" => {} }

      expect(called.pop).to eq(:second)
    end

    it "does nothing for an event nobody subscribed to" do
      expect(subscriber.off("Page.loadEventFired", 1)).to be(true)
    end
  end
end
