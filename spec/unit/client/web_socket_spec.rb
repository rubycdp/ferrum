# frozen_string_literal: true

describe Ferrum::Client::WebSocket do
  # `allocate` skips the constructor so no socket connects; the ivars the send
  # path relies on are set by hand.
  subject(:web_socket) { described_class.allocate }

  # Stands in for the websocket driver and measures how many threads are inside
  # `text` at once — anything above 1 corrupts the frame stream on a real driver.
  let(:frame_probe_class) do
    Class.new do
      def initialize
        @frames = Thread::Queue.new
        @active = Concurrent::AtomicFixnum.new(0)
        @peak = Concurrent::AtomicFixnum.new(0)
      end

      def text(json)
        level = @active.increment
        @peak.update { |peak| [peak, level].max }
        sleep 0.005
        @frames << json
        @active.decrement
      end

      def frames = Array.new(@frames.size) { @frames.pop }

      def peak_concurrent_writes = @peak.value
    end
  end

  let(:frame_probe) { frame_probe_class.new }

  before do
    web_socket.instance_variable_set(:@driver, frame_probe)
    web_socket.instance_variable_set(:@driver_mutex, Mutex.new)
    web_socket.instance_variable_set(:@screenshot_commands, Concurrent::Hash.new)
  end

  describe "#send_message" do
    it "hands the driver the message as JSON" do
      web_socket.send_message(id: 1)
      expect(frame_probe.frames).to eq(['{"id":1}'])
    end

    it "writes one frame at a time" do
      Array.new(8) { |i| Thread.new { web_socket.send_message(id: i) } }.each(&:join)
      expect(frame_probe.peak_concurrent_writes).to eq(1)
    end
  end
end
