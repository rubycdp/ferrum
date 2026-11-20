# frozen_string_literal: true

require "rbconfig"

describe Ferrum::Browser::Options do
  before { Ferrum::Utils::Deprecate.reset! }
  after { Ferrum::Utils::Deprecate.reset! }

  describe ".new" do
    it "warns that :protocol_timeout is ignored" do
      expect { described_class.new(protocol_timeout: 10) }
        .to output(/:protocol_timeout is ignored.*called from #{__FILE__}/m).to_stderr
    end

    it "warns that flatten: false will be removed" do
      expect { described_class.new(flatten: false) }
        .to output(/flatten: false will be removed in Ferrum 0.22.*called from #{__FILE__}/m).to_stderr
    end

    it "stays silent when :flatten is true" do
      expect { described_class.new(flatten: true) }.not_to output.to_stderr
    end
  end

  describe "#protocol_timeout" do
    it "warns and returns the fixed timeout of internal commands" do
      options = described_class.new
      value = nil

      expect { value = options.protocol_timeout }.to output(/:protocol_timeout is ignored/).to_stderr
      expect(value).to eq(Ferrum::Client::PROTOCOL_TIMEOUT)
    end
  end

  describe "#protocol_timeout=" do
    it "warns and leaves the timeout as it is" do
      options = described_class.new(timeout: 3)

      expect { options.protocol_timeout = 10 }.to output(/:protocol_timeout is ignored/).to_stderr
      expect(options.timeout).to eq(3)
    end
  end

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
