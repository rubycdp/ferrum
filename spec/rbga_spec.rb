# frozen_string_literal: true

describe Ferrum::RGBA do
  describe "#new" do
    it "raises ArgumentError for Integer value of alpha" do
      expect do
        Ferrum::RGBA.new(0, 0, 0, 0)
      end.to raise_exception(
        ArgumentError,
        "Wrong alpha value 0 should be Float between 0.0 (fully transparent) and 1.0 (fully opaque)"
      )
    end

    it "raises ArgumentError for wrong value of alpha" do
      expect do
        Ferrum::RGBA.new(0, 0, 0, 2.0)
      end.to raise_exception(
        ArgumentError,
        "Wrong alpha value 2.0 should be Float between 0.0 (fully transparent) and 1.0 (fully opaque)"
      )
    end

    it "raises ArgumentError for wrong value of red" do
      expect do
        Ferrum::RGBA.new(-1, 0, 0, 0.0)
      end.to raise_exception(ArgumentError, "Wrong value of -1 should be Integer from 0 to 255")
    end

    it "raises ArgumentError for wrong value of green" do
      expect do
        Ferrum::RGBA.new(0, 256, 0, 0.0)
      end.to raise_exception(ArgumentError, "Wrong value of 256 should be Integer from 0 to 255")
    end

    it "raises ArgumentError for wrong value of blue" do
      expect do
        Ferrum::RGBA.new(0, 0, 0.0, 0.0)
      end.to raise_exception(ArgumentError, "Wrong value of 0.0 should be Integer from 0 to 255")
    end
  end

  describe "#to_h" do
    it { expect(Ferrum::RGBA.new(0, 0, 0, 0.0).to_h).to eq({ r: 0, g: 0, b: 0, a: 0.0 }) }
    it { expect(Ferrum::RGBA.new(255, 255, 255, 1.0).to_h).to eq({ r: 255, g: 255, b: 255, a: 1.0 }) }
  end
end
