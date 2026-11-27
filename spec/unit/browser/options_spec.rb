# frozen_string_literal: true

require "rbconfig"

describe Ferrum::Browser::Options do
  describe "#timeout" do
    def default_timeout(env)
      script = 'require "ferrum"; print Ferrum::Browser::Options.new.timeout'
      IO.popen(env, [RbConfig.ruby, "-I", "lib", "-e", script], &:read)
    end

    it "keeps the fraction of FERRUM_DEFAULT_TIMEOUT" do
      expect(default_timeout("FERRUM_DEFAULT_TIMEOUT" => "0.5")).to eq("0.5")
    end

    it "defaults to 5 seconds" do
      expect(default_timeout("FERRUM_DEFAULT_TIMEOUT" => nil)).to eq("5.0")
    end
  end

  describe ".const_missing" do
    before { Ferrum::Utils::Deprecate.reset! }

    it "answers BASE_URL_SCHEMA with BASE_URL_SCHEMES and a deprecation warning" do
      expect { expect(described_class::BASE_URL_SCHEMA).to eq(%w[http https]) }
        .to output(/BASE_URL_SCHEMA will be removed in Ferrum 1.0. Use BASE_URL_SCHEMES instead./).to_stderr
    end

    it "raises NameError for another missing constant" do
      expect { described_class::NO_SUCH_CONSTANT }.to raise_error(NameError, /NO_SUCH_CONSTANT/)
    end
  end
end
