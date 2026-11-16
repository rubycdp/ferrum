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

  describe ".within" do
    it "bounds the deadlines made in the block" do
      described_class.within(0.05) do
        expect(described_class.wrap(10).remaining).to be < 1
      end
    end

    it "doesn't change a deadline that expires sooner" do
      described_class.within(10) do
        expect(described_class.wrap(0.05).remaining).to be < 1
      end
    end

    it "shares the deadline passed in when it expires first" do
      deadline = described_class.after(0.05)

      described_class.within(10) { expect(described_class.wrap(deadline)).to be(deadline) }
    end

    it "only shortens the deadline of an enclosing block" do
      described_class.within(0.05) do
        described_class.within(10) { expect(described_class.current.remaining).to be < 1 }
      end
    end

    it "restores the previous deadline afterwards" do
      described_class.within(10) { nil }

      expect(described_class.current).to be_nil
    end

    it "restores the previous deadline when the block raises" do
      expect { described_class.within(10) { raise ArgumentError } }.to raise_error(ArgumentError)
      expect(described_class.current).to be_nil
    end

    it "returns what the block returns" do
      expect(described_class.within(10) { :done }).to eq(:done)
    end

    it "isn't inherited by other threads" do
      seen = described_class.within(10) { Thread.new { described_class.current }.value }

      expect(seen).to be_nil
    end
  end

  describe "#min" do
    it "returns the deadline that expires first" do
      sooner = described_class.after(1)
      later = described_class.after(10)

      expect(sooner.min(later)).to be(sooner)
      expect(later.min(sooner)).to be(sooner)
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
