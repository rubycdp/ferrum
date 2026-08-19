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

  describe "#send_message" do
    before do
      client.instance_variable_set(:@pendings, Concurrent::Hash.new)
    end

    it "waits up to protocol_timeout, independent of the page-level timeout" do
      options = Ferrum::Browser::Options.new(timeout: 100, protocol_timeout: 0.05)
      client.instance_variable_set(:@options, options)
      client.instance_variable_set(
        :@ws, instance_double(Ferrum::Client::WebSocket, send_message: true, messages: Queue.new)
      )

      expect do
        client.send_message(client.build_message("Target.createTarget", {}), async: false)
      end.to raise_error(Ferrum::TimeoutError)
    end

    it "does not time out early just because the page-level timeout is low" do
      options = Ferrum::Browser::Options.new(timeout: 0.05, protocol_timeout: 100)
      client.instance_variable_set(:@options, options)

      # Simulates the response arriving after the (low) page-level timeout has
      # already elapsed, but well inside the (high) protocol timeout.
      ws = instance_double(Ferrum::Client::WebSocket, messages: Queue.new)
      allow(ws).to receive(:send_message) do |message|
        Thread.new do
          sleep 0.1
          client.instance_variable_get(:@pendings)[message[:id]].set({ "result" => { "ok" => true } })
        end
        true
      end
      client.instance_variable_set(:@ws, ws)

      message = client.build_message("Target.createTarget", {})
      expect(client.send_message(message, async: false)).to eq({ "ok" => true })
    end

    it "honors an explicit per-call timeout: over protocol_timeout" do
      options = Ferrum::Browser::Options.new(protocol_timeout: 100)
      client.instance_variable_set(:@options, options)
      client.instance_variable_set(
        :@ws, instance_double(Ferrum::Client::WebSocket, send_message: true, messages: Queue.new)
      )

      message = client.build_message("Page.navigate", {})
      expect do
        client.send_message(message, async: false, timeout: 0.05)
      end.to raise_error(Ferrum::TimeoutError)
    end
  end
end
