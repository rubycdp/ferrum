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

    it "is left out of Context#workers once detached" do
      page.go_to

      page.execute <<~JS
        new Worker(URL.createObjectURL(new Blob(
          ["self.onmessage = () => {}"],
          { type: "application/javascript" }
        )))
      JS

      target = wait_for_target(&:worker?)
      wait_for { browser.workers }.to contain_exactly(target.worker)
      page.command("Target.detachFromTarget", sessionId: target.session_id)

      wait_for { browser.workers }.to be_empty
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
      page.evaluate(%(await navigator.serviceWorker.register("/sw.js")), timeout: 5)

      target = wait_for_target(&:service_worker?)

      expect(target.url).to end_with("/sw.js")
      expect(target.connected?).to eq(false)
      expect(browser.service_workers).to contain_exactly(target)
    end

    it "detaches from them so Chrome can terminate them" do
      page.go_to
      page.execute(%(await navigator.serviceWorker.register("/sw.js")), timeout: 5)
      target = wait_for_target(&:service_worker?)

      wait_for do
        browser.client.command("Target.getTargets")["targetInfos"]
               .select { |info| info["type"] == "service_worker" }.map { |info| info["attached"] }
      end.to eq([false])
      expect(target.session_id).to be_nil
    end

    it "raises when connected to without attaching first" do
      page.go_to
      page.execute(%(await navigator.serviceWorker.register("/sw.js")), timeout: 5)
      target = wait_for_target(&:service_worker?)
      wait_for { target.session_id }.to be_nil

      expect { target.worker }.to raise_error(Ferrum::NoSuchTargetError, /attach_target/)
    end

    it "connects on demand through Context#attach_target, keeping it alive" do
      page.go_to
      page.evaluate(%(await navigator.serviceWorker.register("/sw.js")), timeout: 5)

      target = wait_for_target(&:service_worker?)
      browser.attach_target(target.id)

      expect(target.worker.evaluate("1 + 1")).to eq(2)
    end
  end
end
