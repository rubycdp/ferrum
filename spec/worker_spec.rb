# frozen_string_literal: true

describe Ferrum::Worker do
  describe "#console" do
    it "collects its console messages" do
      page.go_to

      page.execute <<~JS
        new Worker(URL.createObjectURL(new Blob(
          ["self.onmessage = () => {}"],
          { type: "application/javascript" }
        )))
      JS

      worker = wait_for_target(&:worker?).worker
      worker.execute(%(console.warn("from worker")))

      wait_for { worker.console.map(&:text) }.to eq(["from worker"])
      expect(worker.console.first).to be_warning
    end
  end
end
