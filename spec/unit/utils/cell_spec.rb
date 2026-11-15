# frozen_string_literal: true

describe Ferrum::Utils::Cell do
  subject(:cell) { described_class.new }

  describe ".set" do
    it "builds a cell that holds the value" do
      cell = described_class.set(1)

      expect(cell).to be_set
      expect(cell.value).to eq(1)
    end
  end

  describe "#wait" do
    it "returns true at once when a value is stored" do
      cell.set(1)

      expect(cell.wait(0)).to be(true)
    end

    it "returns false when the timeout is reached" do
      expect(cell.wait(0.05)).to be(false)
    end

    it "wakes up when another thread sets a value" do
      Thread.new do
        sleep(0.05)
        cell.set(42)
      end

      expect(cell.wait(5)).to be(true)
      expect(cell.value).to eq(42)
    end

    it "wakes up every waiter when the cell is closed" do
      waiters = Array.new(2) { Thread.new { cell.wait(5) } }
      sleep(0.05)

      cell.close

      expect(waiters.map(&:value)).to eq([false, false])
    end

    it "doesn't block once closed" do
      cell.close

      expect(cell.wait(5)).to be(false)
    end

    it "takes a deadline" do
      expect(cell.wait(Ferrum::Deadline.after(0.05))).to be(false)
    end
  end

  describe "#clear" do
    it "empties the cell" do
      cell.set(1)

      cell.clear

      expect(cell).not_to be_set
      expect(cell.value).to be_nil
    end

    it "returns the next generation" do
      expect { cell.clear }.to change(cell, :generation).by(1)
    end
  end

  describe "#set" do
    it "replaces the stored value" do
      cell.set(1)
      cell.set(2)

      expect(cell.value).to eq(2)
    end
  end
end
