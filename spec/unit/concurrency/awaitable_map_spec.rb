# frozen_string_literal: true

describe Ferrum::Concurrency::AwaitableMap do
  subject(:map) { described_class.new }

  describe "#await" do
    it "returns the value at once when the key is stored" do
      map["a"] = 1

      expect(map.await("a", 0)).to eq(1)
    end

    it "returns nil when the timeout is reached" do
      expect(map.await("a", 0.05)).to be_nil
    end

    it "wakes up when another thread stores the key" do
      Thread.new do
        sleep(0.05)
        map["a"] = 42
      end

      expect(map.await("a", 5)).to eq(42)
    end

    it "keeps waiting while other keys are stored" do
      Thread.new do
        sleep(0.05)
        map["b"] = 1
        sleep(0.05)
        map["a"] = 2
      end

      expect(map.await("a", 5)).to eq(2)
    end

    it "takes a deadline" do
      expect(map.await("a", Ferrum::Deadline.after(0.05))).to be_nil
    end
  end

  describe "#fulfill" do
    it "stores the value of an expected key" do
      map.expect("a")

      expect(map.fulfill("a", 1)).to be(true)
      expect(map["a"]).to eq(1)
    end

    it "drops the value of a key nobody expects" do
      expect(map.fulfill("a", 1)).to be(false)
      expect(map).not_to be_key("a")
    end

    it "drops the value once the key was deleted" do
      map.expect("a")
      map.delete("a")

      expect(map.fulfill("a", 1)).to be(false)
    end

    it "wakes up a thread waiting for the key" do
      map.expect("a")
      Thread.new do
        sleep(0.05)
        map.fulfill("a", 42)
      end

      expect(map.await("a", 5)).to eq(42)
    end
  end

  describe "#expecting?" do
    it "is true for an expected key until it is deleted" do
      map.expect("a")
      expect(map).to be_expecting("a")

      map.delete("a")
      expect(map).not_to be_expecting("a")
    end
  end

  describe "#close" do
    it "wakes up every waiter" do
      waiters = Array.new(2) { Thread.new { map.await("a", 5) } }
      sleep(0.05)

      map.close

      expect(waiters.map(&:value)).to eq([nil, nil])
    end

    it "makes await return at once" do
      map.close

      expect(map.await("a", 5)).to be_nil
    end
  end

  describe "#delete" do
    it "removes the key and returns its value" do
      map["a"] = 1

      expect(map.delete("a")).to eq(1)
      expect(map).not_to be_key("a")
    end
  end

  describe "#values" do
    it "returns the stored values" do
      map["a"] = 1
      map["b"] = 2

      expect(map.values).to eq([1, 2])
    end
  end
end
