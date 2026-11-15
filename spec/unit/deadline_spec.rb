# frozen_string_literal: true

describe Ferrum::Deadline do
  describe ".after" do
    it "starts a deadline that expires after the given seconds" do
      deadline = described_class.after(0.05)

      expect(deadline).not_to be_expired
      sleep(0.06)
      expect(deadline).to be_expired
    end
  end

  describe ".wrap" do
    it "starts a deadline for a number of seconds" do
      expect(described_class.wrap(10).remaining).to be_within(0.5).of(10)
    end

    it "returns a deadline as is" do
      deadline = described_class.after(10)

      expect(described_class.wrap(deadline)).to be(deadline)
    end
  end

  describe "#remaining" do
    it "counts down" do
      deadline = described_class.after(10)
      first = deadline.remaining

      sleep(0.02)

      expect(deadline.remaining).to be < first
    end

    it "is zero once the deadline has expired" do
      expect(described_class.after(-1).remaining).to eq(0.0)
    end
  end

  describe "#expired?" do
    it "is false before the deadline" do
      expect(described_class.after(10)).not_to be_expired
    end

    it "is true after the deadline" do
      expect(described_class.after(-1)).to be_expired
    end
  end
end
