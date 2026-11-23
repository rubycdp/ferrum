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

  describe ".renamed_env" do
    around do |example|
      keys = %w[FERRUM_NEW_WAIT FERRUM_OLD_WAIT]
      saved = keys.to_h { |k| [k, ENV.fetch(k, nil)] }
      keys.each { |k| ENV.delete(k) }
      example.run
      saved.each { |k, v| ENV[k] = v }
    end

    def read
      described_class.renamed_env("FERRUM_NEW_WAIT", %w[FERRUM_OLD_WAIT], 0.1)
    end

    it "returns the default when none is set" do
      expect(read).to eq(0.1)
    end

    it "returns the current variable without warning" do
      ENV["FERRUM_NEW_WAIT"] = "0.5"
      expect { expect(read).to eq(0.5) }.not_to output.to_stderr
    end

    it "returns the old variable and warns about it" do
      ENV["FERRUM_OLD_WAIT"] = "0.3"
      described_class.reset!
      expect { expect(read).to eq(0.3) }.to output(/FERRUM_OLD_WAIT is replaced by FERRUM_NEW_WAIT/).to_stderr
    end

    it "prefers the current variable over the old one" do
      ENV["FERRUM_NEW_WAIT"] = "0.5"
      ENV["FERRUM_OLD_WAIT"] = "0.3"
      expect(read).to eq(0.5)
    end
  end
end
