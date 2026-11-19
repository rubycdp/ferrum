# frozen_string_literal: true

describe Ferrum::Page do
  describe "#wait_for_reload" do
    subject(:page) { described_class.allocate }

    let(:idle) { Ferrum::Concurrency::Cell.set(true) }

    before { page.instance_variable_set(:@idle, idle) }

    it "marks the page idle again when no reload came" do
      page.wait_for_reload(0.05)

      expect(idle).to be_set
    end

    it "leaves the page loading when a navigation began meanwhile" do
      Thread.new do
        sleep(0.02)
        idle.clear
      end

      page.wait_for_reload(0.1)

      expect(idle).not_to be_set
    end
  end
end
