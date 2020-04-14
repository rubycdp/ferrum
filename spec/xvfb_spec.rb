module Ferrum::Xvfb
  describe Process do
    let(:default_options) { { window_size: [1024, 768 ] } }
    let(:options) { default_options }
    subject { described_class.new(options).start! }

    after do
      subject.clean_up_proc.call
      expect(subject).not_to be_alive
      expect(subject).not_to be_process_alive
    end

    it "starts xvfb" do
      subject

      expect(subject).to be_alive
    end

    context "no window size supplied" do
      let(:default_options) { {} }

      it "starts xvfb" do
        subject

        expect(subject.screen_size).to eq "1024x768x24"
        expect(subject).to be_alive
      end
    end
  end
end