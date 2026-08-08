# frozen_string_literal: true

describe Ferrum::Client do
  # `allocate` skips the constructor so no browser boots; the ivars the id
  # mint relies on are set by hand.
  subject(:client) { described_class.allocate }

  before do
    client.instance_variable_set(:@command_id, 0)
    client.instance_variable_set(:@command_id_mutex, Mutex.new)
  end

  describe "#build_message" do
    it "carries the method and params" do
      expect(client.build_message("Page.enable", foo: 1)).to include(method: "Page.enable", params: { foo: 1 })
    end

    it "mints sequential ids for sequential commands" do
      ids = Array.new(3) { client.build_message("Page.enable", {})[:id] }
      expect(ids).to eq([1, 2, 3])
    end

    context "with the id increment window held open" do
      # Stretches the read-modify-write of `@command_id += 1` so the
      # lost-update race is deterministic instead of scheduler-dependent.
      let(:racy_counter_class) do
        Class.new do
          attr_reader :to_i

          def initialize(value)
            @to_i = value
          end

          def +(other)
            read = @to_i
            sleep 0.005
            self.class.new(read + other)
          end
        end
      end

      before { client.instance_variable_set(:@command_id, racy_counter_class.new(0)) }

      it "mints a unique id per command across concurrent threads" do
        ids = Queue.new
        Array.new(8) { Thread.new { ids << client.build_message("Page.enable", {})[:id].to_i } }.each(&:join)
        expect(Array.new(8) { ids.pop }).to match_array((1..8).to_a)
      end
    end
  end
end
