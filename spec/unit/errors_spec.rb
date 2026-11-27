# frozen_string_literal: true

describe Ferrum do
  describe ".const_missing" do
    before { Ferrum::Utils::Deprecate.reset! }

    it "answers NotImplementedError with a Ferrum error and a deprecation warning" do
      expect { expect(Ferrum::NotImplementedError).to be < Ferrum::Error }
        .to output(/Ferrum::NotImplementedError will be removed in Ferrum 1.0, nothing raises it./).to_stderr
    end

    it "raises NameError for another missing constant" do
      expect { Ferrum::NoSuchConstant }.to raise_error(NameError, /NoSuchConstant/)
    end
  end
end
