# frozen_string_literal: true

describe Ferrum::Utils::Deprecate do
  describe ".positional" do
    it "returns the keyword's value without warning when nothing is passed positionally" do
      expect { expect(described_class.positional(:timeout, nil, 3)).to eq(3) }.not_to output.to_stderr
    end

    it "returns the positional value and warns about it" do
      described_class.reset!

      expect { expect(described_class.positional(:timeout, 2, 3)).to eq(2) }
        .to output(/Passing timeout positionally will be removed in Ferrum 0\.22/).to_stderr
    end
  end
end
