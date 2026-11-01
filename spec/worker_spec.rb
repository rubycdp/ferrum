# frozen_string_literal: true

describe Ferrum::Worker do
  def spawn_worker
    page.go_to
    page.execute <<~JS
      new Worker(URL.createObjectURL(new Blob(
        ["self.onmessage = () => {}"],
        { type: "application/javascript" }
      )))
    JS
    wait_for_target(&:worker?).worker
  end

  describe "#console" do
    it "collects its console messages" do
      worker = spawn_worker
      worker.execute(%(console.warn("from worker")))

      wait_for { worker.console.map(&:text) }.to eq(["from worker"])
      expect(worker.console.first).to be_warning
    end
  end

  describe "#timeout" do
    it "returns the browser's timeout" do
      expect(spawn_worker.timeout).to eq(browser.timeout)
    end
  end

  describe "#command" do
    it "sends a CDP command to the worker" do
      result = spawn_worker.command("Runtime.evaluate", expression: "typeof WorkerGlobalScope")

      expect(result.dig("result", "value")).to eq("function")
    end
  end

  describe "#main_frame" do
    it "returns nil" do
      expect(spawn_worker.main_frame).to be_nil
    end
  end
end
