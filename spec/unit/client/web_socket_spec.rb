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
    web_socket.instance_variable_set(:@mutex, Mutex.new)
    web_socket.instance_variable_set(:@encoded, [])
  end

  describe "reader cleanup" do
    it "closes the socket and writer when the peer closes the connection" do
      socket, peer = Socket.pair(:UNIX, :STREAM, 0)
      messages = Queue.new
      outgoing = Queue.new
      web_socket.instance_variable_set(:@sock, socket)
      web_socket.instance_variable_set(:@messages, messages)
      web_socket.instance_variable_set(:@outgoing, outgoing)

      web_socket.send(:start_writer)
      web_socket.send(:start)
      reader = web_socket.instance_variable_get(:@thread)
      writer = web_socket.instance_variable_get(:@writer)

      peer.close

      expect(reader.join(1)).to eq(reader)
      expect(writer.join(1)).to eq(writer)
      expect(socket).to be_closed
      expect(messages).to be_closed
      expect(outgoing).to be_closed
    ensure
      peer&.close unless peer&.closed?
      socket&.close unless socket&.closed?
    end
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
