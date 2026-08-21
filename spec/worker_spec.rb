# frozen_string_literal: true

describe Ferrum::Worker do
  def wait_for_target(&block)
    start = Ferrum::Utils::ElapsedTime.monotonic_time
    target = nil

    until target
      target = browser.targets.values.find(&block)
      raise Ferrum::TimeoutError if Ferrum::Utils::ElapsedTime.timeout?(start, browser.timeout)

      sleep 0.05
    end

    target
  end

  describe "dedicated workers" do
    it "is discovered, connected to, and reachable through Context#workers" do
      page.go_to

      page.execute <<~JS
        new Worker(URL.createObjectURL(new Blob(
          ["self.onmessage = () => self.postMessage(1 + 1)"],
          { type: "application/javascript" }
        )))
      JS

      target = wait_for_target(&:worker?)

      expect(target.url).to start_with("blob:")
      expect(target.connected?).to eq(true)
      expect(browser.workers).to contain_exactly(target.worker)
      expect(target.worker.evaluate("1 + 1")).to eq(2)
    end
  end

  describe "shared workers" do
    it "is discovered, connected to, and reachable through Context#workers" do
      page.go_to

      page.execute <<~JS
        new SharedWorker(URL.createObjectURL(new Blob(
          ["self.onconnect = () => {}"],
          { type: "application/javascript" }
        )))
      JS

      target = wait_for_target(&:shared_worker?)

      expect(target.connected?).to eq(true)
      expect(browser.workers).to contain_exactly(target.worker)
      expect(target.worker.evaluate("1 + 1")).to eq(2)
    end
  end

  describe "service workers" do
    it "discovers registered service workers without connecting to them" do
      page.go_to
      page.evaluate_async(%(navigator.serviceWorker.register("/sw.js").then(arguments[0])), 5)

      target = wait_for_target(&:service_worker?)

      expect(target.url).to end_with("/sw.js")
      expect(target.connected?).to eq(false)
      expect(browser.service_workers).to contain_exactly(target)
    end

    it "connects on demand through Context#attach_target, keeping it alive" do
      page.go_to
      page.evaluate_async(%(navigator.serviceWorker.register("/sw.js").then(arguments[0])), 5)

      target = wait_for_target(&:service_worker?)
      browser.attach_target(target.id)

      expect(target.worker.evaluate("1 + 1")).to eq(2)
    end
  end
end
