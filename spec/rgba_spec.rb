# frozen_string_literal: true

describe Ferrum::RGBA do
  describe ".new" do
    it "raises ArgumentError for Integer value of alpha" do
      expect do
        Ferrum::RGBA.new(0, 0, 0, 0)
      end.to raise_exception(
        ArgumentError,
        "Alpha should be a Float from 0.0 (fully transparent) to 1.0 (fully opaque), got 0"
      )
    end

    it "raises ArgumentError for wrong value of alpha" do
      expect do
        Ferrum::RGBA.new(0, 0, 0, 2.0)
      end.to raise_exception(
        ArgumentError,
        "Alpha should be a Float from 0.0 (fully transparent) to 1.0 (fully opaque), got 2.0"
      )
    end

    it "raises ArgumentError for wrong value of red" do
      expect do
        Ferrum::RGBA.new(-1, 0, 0, 0.0)
      end.to raise_exception(ArgumentError, "Color should be an Integer from 0 to 255, got -1")
    end

    it "raises ArgumentError for wrong value of green" do
      expect do
        Ferrum::RGBA.new(0, 256, 0, 0.0)
      end.to raise_exception(ArgumentError, "Color should be an Integer from 0 to 255, got 256")
    end

    it "raises ArgumentError for wrong value of blue" do
      expect do
        Ferrum::RGBA.new(0, 0, 0.0, 0.0)
      end.to raise_exception(ArgumentError, "Color should be an Integer from 0 to 255, got 0.0")
    end
  end

  describe "#to_h" do
    it "returns the channels as a hash" do
      expect(Ferrum::RGBA.new(0, 0, 0, 0.0).to_h).to eq({ r: 0, g: 0, b: 0, a: 0.0 })
      expect(Ferrum::RGBA.new(255, 255, 255, 1.0).to_h).to eq({ r: 255, g: 255, b: 255, a: 1.0 })
    end
  end
end
