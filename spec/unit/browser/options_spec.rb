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
end
