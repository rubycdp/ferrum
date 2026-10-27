# frozen_string_literal: true

describe Ferrum::Log do
  describe "#browser" do
    it "keeps lines whole when written from several threads at once" do
      io = StringIO.new
      log = described_class.new(io)
      lines = Array.new(8) { |i| i.to_s * 512 }

      lines.map { |line| Thread.new { 200.times { log.browser(line) } } }.each(&:join)

      expect(io.string.lines(chomp: true)).to all(satisfy { |l| lines.include?(l) })
      expect(io.string.lines.size).to eq(8 * 200)
    end
  end
end
