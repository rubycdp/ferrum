# frozen_string_literal: true

describe Ferrum::Browser::Options do
  describe "#ignore_js_errors" do
    it "defaults to no patterns" do
      expect(described_class.new.ignore_js_errors).to eq([])
    end

    it "keeps the given patterns" do
      expect(described_class.new(ignore_js_errors: [/omg/, /zomg/]).ignore_js_errors).to eq([/omg/, /zomg/])
    end

    it "rejects a single pattern that is not wrapped in an Array" do
      expect { described_class.new(ignore_js_errors: /omg/) }
        .to raise_error(ArgumentError, "ignore_js_errors must be an Array of Regexp")
    end

    it "rejects nil" do
      expect { described_class.new(ignore_js_errors: nil) }
        .to raise_error(ArgumentError, "ignore_js_errors must be an Array of Regexp")
    end

    it "rejects a String pattern" do
      expect { described_class.new(ignore_js_errors: ["omg"]) }
        .to raise_error(ArgumentError, "ignore_js_errors must be an Array of Regexp")
    end
  end

  describe "#ignore_js_error?" do
    let(:options) { described_class.new(ignore_js_errors: [/Transition was skipped/, /^ReferenceError: /]) }

    it "matches a message any pattern matches" do
      expect(options.ignore_js_error?("ReferenceError: omg is not defined")).to be(true)
    end

    it "does not match a message no pattern covers" do
      expect(options.ignore_js_error?("TypeError: Cannot read properties of undefined")).to be(false)
    end

    it "matches nothing by default" do
      expect(described_class.new.ignore_js_error?("ReferenceError: omg is not defined")).to be(false)
    end
  end

  describe "#protocol_timeout" do
    it "defaults to a low value, sufficient for internal CDP bookkeeping" do
      options = described_class.new

      expect(options.protocol_timeout).to eq(Ferrum::Browser::Options::DEFAULT_PROTOCOL_TIMEOUT)
    end

    it "does not shrink when :timeout is lowered" do
      options = described_class.new(timeout: 0.1)

      expect(options.timeout).to eq(0.1)
      expect(options.protocol_timeout).to eq(Ferrum::Browser::Options::DEFAULT_PROTOCOL_TIMEOUT)
    end

    it "is configurable independently of :timeout" do
      options = described_class.new(timeout: 10, protocol_timeout: 60)

      expect(options.timeout).to eq(10)
      expect(options.protocol_timeout).to eq(60)
    end
  end
end
