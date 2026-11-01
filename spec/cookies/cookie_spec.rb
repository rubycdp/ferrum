# frozen_string_literal: true

describe Ferrum::Cookies::Cookie do
  let(:attributes) do
    {
      "name" => "OGP",
      "value" => "-19027681:",
      "domain" => ".google.com",
      "path" => "/",
      "sameSite" => "Lax",
      "expires" => 1_691_287_370,
      "size" => 13,
      "httpOnly" => false,
      "secure" => false,
      "session" => false,
      "priority" => "Medium",
      "sameParty" => false,
      "sourceScheme" => "Secure",
      "sourcePort" => 443
    }
  end

  subject { described_class.new(attributes) }

  describe "#name" do
    it "returns the 'name' attribute" do
      expect(subject.name).to eq(attributes["name"])
    end
  end

  describe "#value" do
    it "returns the 'value' attribute" do
      expect(subject.value).to eq(attributes["value"])
    end
  end

  describe "#domain" do
    it "returns the 'domain' attribute" do
      expect(subject.domain).to eq(attributes["domain"])
    end
  end

  describe "#path" do
    it "returns the 'path' attribute" do
      expect(subject.path).to eq(attributes["path"])
    end
  end

  describe "#samesite" do
    it "returns the 'sameSite' attribute" do
      expect(subject.samesite).to eq(attributes["sameSite"])
    end
  end

  describe "#size" do
    it "returns the 'size' attribute" do
      expect(subject.size).to eq(attributes["size"])
    end
  end

  describe "#secure?" do
    it "returns the 'secure' attribute" do
      expect(subject.secure?).to eq(attributes["secure"])
    end
  end

  describe "#httponly?" do
    it "returns the 'httpOnly' attribute" do
      expect(subject.httponly?).to eq(attributes["httpOnly"])
    end
  end

  describe "#session?" do
    it "returns the 'session' attribute" do
      expect(subject.session?).to eq(attributes["session"])
    end
  end

  describe "#expires" do
    it "parses the 'expires' attribute as a Time object" do
      expect(subject.expires).to eq(Time.at(attributes["expires"]))
    end

    context "when the 'expires' attribute is negative" do
      let(:attributes) { { "expires" => -1 } }

      it "returns nil" do
        expect(subject.expires).to be(nil)
      end
    end
  end

  describe "#priority" do
    it "returns the 'priority' attribute" do
      expect(subject.priority).to eq(attributes["priority"])
    end
  end

  describe "#sameparty?" do
    it "returns the 'sameParty' attribute" do
      expect(subject.sameparty?).to eq(attributes["sameParty"])
    end
  end

  describe "#source_scheme" do
    it "returns the 'sourceScheme' attribute" do
      expect(subject.source_scheme).to eq(attributes["sourceScheme"])
    end
  end

  describe "#source_port" do
    it "returns the 'sourcePort' attribute" do
      expect(subject.source_port).to eq(attributes["sourcePort"])
    end
  end

  describe "#==" do
    context "when the other cookie has the same attributes" do
      let(:other) { described_class.new(attributes) }

      it "returns true" do
        expect(subject == other).to be(true)
      end
    end

    context "when the other cookie has different attributes" do
      let(:other) do
        described_class.new("name" => "other", "value" => "other")
      end

      it "returns false" do
        expect(subject == other).to be(false)
      end
    end

    context "when given another type of object" do
      let(:other) { Object.new }

      it "returns false" do
        expect(subject == other).to be(false)
      end
    end
  end

  describe "#to_s" do
    let(:name)  { "foo" }
    let(:value) { "bar" }

    context "when only 'name' and 'value' attributes are set" do
      let(:attributes) do
        {
          "name" => name,
          "value" => value
        }
      end

      it "returns only 'name=value'" do
        expect(subject.to_s).to eq("#{name}=#{value}")
      end
    end

    context "when the 'domain' attribute is set" do
      let(:domain) { "example.com" }
      let(:attributes) do
        {
          "name" => name,
          "value" => value,
          "domain" => domain
        }
      end

      it "includes the 'Domain=' attribute in the String" do
        expect(subject.to_s).to eq("#{name}=#{value}; Domain=#{domain}")
      end
    end

    context "when the 'path' attribute is set" do
      let(:path) { "/" }
      let(:attributes) do
        {
          "name" => name,
          "value" => value,
          "path" => path
        }
      end

      it "includes the 'Path=' attribute in the String" do
        expect(subject.to_s).to eq("#{name}=#{value}; Path=#{path}")
      end
    end

    context "when the 'expires' attribute is set" do
      let(:expires) { 1_691_287_370 }
      let(:attributes) do
        {
          "name" => name,
          "value" => value,
          "expires" => expires
        }
      end

      it "includes the 'Expires=' attribute and HTTP formatted time in the String" do
        expect(subject.to_s).to eq("#{name}=#{value}; Expires=#{Time.at(expires).httpdate}")
      end
    end

    context "when the 'httpOnly' attribute is set" do
      let(:attributes) do
        {
          "name" => name,
          "value" => value,
          "httpOnly" => true
        }
      end

      it "includes the 'httpOnly' flag in the String" do
        expect(subject.to_s).to eq("#{name}=#{value}; httpOnly")
      end
    end

    context "when the 'secure' attribute is set" do
      let(:attributes) do
        {
          "name" => name,
          "value" => value,
          "secure" => true
        }
      end

      it "includes the 'Secure' flag in the String" do
        expect(subject.to_s).to eq("#{name}=#{value}; Secure")
      end
    end
  end

  describe "#to_h" do
    it "returns #attributes" do
      expect(subject.to_h).to eq(subject.attributes)
    end
  end
end
