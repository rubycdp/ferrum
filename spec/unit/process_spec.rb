# frozen_string_literal: true

module Ferrum
  class Browser
    describe Process do
      subject { Browser.new(port: 6000, host: "127.0.0.1") }

      unless Utils::Platform.windows?
        it "forcibly kills the child if it does not respond to SIGTERM" do
          allow(::Process).to receive_messages(spawn: 5678)
          allow(::Process).to receive(:wait).and_return(nil)
          allow(Client).to receive(:new).and_return(double.as_null_object)

          allow_any_instance_of(Process).to receive(:parse_ws_url)

          subject.send(:start)

          expect(::Process).to receive(:kill).with("USR1", 5678).ordered
          expect(::Process).to receive(:kill).with("KILL", 5678).ordered

          subject.quit
        end
      end
    end
  end
end
