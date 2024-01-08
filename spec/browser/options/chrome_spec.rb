# frozen_string_literal: true

describe Ferrum::Browser::Options::Chrome do
  def reload_chrome_class
    described_class.constants(false).each do |const|
      described_class.send(:remove_const, const)
    end
    load 'ferrum/browser/options/chrome.rb'
  end

  describe "DEFAULT_OPTIONS" do
    it "includes `disable-gpu` flag only on windows" do
      allow(Ferrum::Utils::Platform).to receive(:windows?).and_return(true)
      reload_chrome_class
      expect(described_class::DEFAULT_OPTIONS).to include("disable-gpu" => nil)

      allow(Ferrum::Utils::Platform).to receive(:windows?).and_return(false)
      reload_chrome_class
      expect(described_class::DEFAULT_OPTIONS).not_to include("disable-gpu" => nil)

      allow(Ferrum::Utils::Platform).to receive(:windows?).and_call_original
      reload_chrome_class
    end

    it "includes `use-angle=metal` flag only on mac arm" do
      allow(Ferrum::Utils::Platform).to receive(:mac_arm?).and_return(true)
      reload_chrome_class
      expect(described_class::DEFAULT_OPTIONS).to include("use-angle" => "metal")

      allow(Ferrum::Utils::Platform).to receive(:mac_arm?).and_return(false)
      reload_chrome_class
      expect(described_class::DEFAULT_OPTIONS).not_to include("use-angle" => "metal")

      allow(Ferrum::Utils::Platform).to receive(:mac_arm?).and_call_original
      reload_chrome_class
    end
  end
end
