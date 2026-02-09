# frozen_string_literal: true

describe Ferrum::Browser::Options::Chrome do
  let(:defaults) { described_class.options }
  let(:options) { Ferrum::Browser::Options.new }

  describe "#merge_default" do
    it "includes --disable-gpu flag on windows" do
      allow(Ferrum::Utils::Platform).to receive(:windows?).and_return(true)
      expect(defaults.merge_default({}, options)).to include("disable-gpu" => nil)
    end

    it "excludes --disable-gpu flag on other platforms" do
      allow(Ferrum::Utils::Platform).to receive(:windows?).and_return(false)
      expect(defaults.merge_default({}, options)).not_to include("disable-gpu" => nil)
    end

    it "includes --use-angle=metal flag on mac arm" do
      allow(Ferrum::Utils::Platform).to receive(:mac_arm?).and_return(true)
      expect(defaults.merge_default({}, options)).to include("use-angle" => "metal")
    end

    it "excludes --use-angle=metal flag on mac arm" do
      allow(Ferrum::Utils::Platform).to receive(:mac_arm?).and_return(false)
      expect(defaults.merge_default({}, options)).not_to include("use-angle" => "metal")
    end
  end

  describe ".version" do
    it "returns an executable version" do
      "Google Chrome for Testing 145.0.7632.46"
      expect(described_class.version).to match(/(Chromium|Chrome)(?: for Testing)? \d/)
    end
  end
end
