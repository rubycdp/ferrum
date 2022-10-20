# frozen_string_literal: true

describe Ferrum::Browser::VersionInfo do
  let(:protocol_version) { "1.3" }
  let(:product)          { "HeadlessChrome/106.0.5249.91" }
  let(:revision)         { "@fa96d5f07b1177d1bf5009f647a5b8c629762157" }
  let(:user_agent)       do
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 " \
      "(KHTML, like Gecko) HeadlessChrome/106.0.5249.91 Safari/537.36"
  end
  let(:js_version) { "10.6.194.17" }
  let(:properties) do
    {
      "protocolVersion" => protocol_version,
      "product" => product,
      "revision" => revision,
      "userAgent" => user_agent,
      "jsVersion" => js_version
    }
  end

  subject { described_class.new(properties) }

  describe "#protocol_version" do
    it "must return the protocolVersion property" do
      expect(subject.protocol_version).to eq(properties["protocolVersion"])
    end
  end

  describe "#product" do
    it "must return the product property" do
      expect(subject.product).to eq(properties["product"])
    end
  end

  describe "#revision" do
    it "must return the revision property" do
      expect(subject.revision).to eq(properties["revision"])
    end
  end

  describe "#user_agent" do
    it "must return the userAgent property" do
      expect(subject.user_agent).to eq(properties["userAgent"])
    end
  end

  describe "#js_version" do
    it "must return the jsVersion property" do
      expect(subject.js_version).to eq(properties["jsVersion"])
    end
  end
end
