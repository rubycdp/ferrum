# frozen_string_literal: true

describe Ferrum::Downloads do
  describe "#wait" do
    subject(:downloads) { described_class.allocate }

    let(:idle) { Ferrum::Concurrency::Cell.set(true) }

    before { downloads.instance_variable_set(:@idle, idle) }

    it "marks downloads idle again when none began" do
      downloads.wait(0.05)

      expect(idle).to be_set
    end

    it "leaves a download in flight as it is when the timeout is reached" do
      downloads.wait(0.05) { idle.clear }

      expect(idle).not_to be_set
    end
  end
end
