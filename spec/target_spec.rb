# frozen_string_literal: true

describe Ferrum::Target do
  def target_of(page)
    browser.targets[page.target_id]
  end

  def open_popup
    page.go_to
    page.execute(%(window.open("/simple", "popup")))
    wait_for_target { |target| target.opener_id == page.target_id }
  end

  def spawn_worker(type)
    constructor = { "worker" => "Worker", "shared_worker" => "SharedWorker" }.fetch(type)
    page.go_to
    page.execute(<<~JS)
      new #{constructor}(URL.createObjectURL(new Blob(["self.onconnect = self.onmessage = () => {}"],
                                               { type: "application/javascript" })))
    JS
    wait_for_target { |target| target.type == type }
  end

  def register_service_worker
    page.go_to
    page.execute(%(await navigator.serviceWorker.register("/sw.js")), timeout: 5)
    wait_for_target(&:service_worker?)
  end

  describe "#connected?" do
    it "returns false until the target is connected to" do
      target = browser.create_target

      expect(target).not_to be_connected
      target.page
      expect(target).to be_connected
    end
  end

  describe "#page" do
    it "connects to the target as a page" do
      target = browser.create_target

      expect(target.page.target_id).to eq(target.id)
      expect(target.page).to equal(target.page)
    end
  end

  describe "#worker" do
    it "raises for a service worker that isn't attached" do
      target = register_service_worker
      wait_for { target.session_id }.to be_nil

      expect { target.worker }.to raise_error(Ferrum::NoSuchTargetError, /attach_target/)
    end
  end

  describe "#id" do
    it "returns the id of the target" do
      expect(target_of(page).id).to eq(page.target_id)
    end
  end

  describe "#type" do
    it "returns page for a page" do
      expect(target_of(page).type).to eq("page")
    end

    it "returns worker for a dedicated worker" do
      expect(spawn_worker("worker").type).to eq("worker")
    end
  end

  describe "#url" do
    it "returns the url of the page" do
      page.go_to("/simple")

      wait_for { target_of(page).url }.to eq(base_url("/simple"))
    end
  end

  describe "#opener_id" do
    it "returns the id of the page that opened a popup" do
      expect(open_popup.opener_id).to eq(page.target_id)
    end

    it "returns nil for a page created directly" do
      expect(target_of(page).opener_id).to be_nil
    end
  end

  describe "#parent_id" do
    it "returns the id of the page that spawned a worker" do
      expect(spawn_worker("worker").parent_id).to eq(page.target_id)
    end
  end

  describe "#context_id" do
    it "returns the id of the context the target belongs to" do
      context = browser.contexts.create

      page = context.create_page

      expect(context.targets[page.target_id].context_id).to eq(context.id)
    end
  end

  describe "#window?" do
    it "returns true for a popup" do
      expect(open_popup).to be_window
    end

    it "returns false for a page created directly" do
      expect(target_of(page)).not_to be_window
    end
  end

  describe "#page?" do
    it "returns true for a page" do
      expect(target_of(page)).to be_page
    end

    it "returns false for a worker" do
      expect(spawn_worker("worker")).not_to be_page
    end
  end

  describe "#worker?" do
    it "returns true for a dedicated worker" do
      expect(spawn_worker("worker")).to be_worker
    end

    it "returns false for a shared worker" do
      expect(spawn_worker("shared_worker")).not_to be_worker
    end
  end

  describe "#shared_worker?" do
    it "returns true for a shared worker" do
      expect(spawn_worker("shared_worker")).to be_shared_worker
    end

    it "returns false for a dedicated worker" do
      expect(spawn_worker("worker")).not_to be_shared_worker
    end
  end

  describe "#service_worker?" do
    it "returns true for a service worker" do
      expect(register_service_worker).to be_service_worker
    end

    it "returns false for a page" do
      expect(target_of(page)).not_to be_service_worker
    end
  end

  describe "#command" do
    it "sends a CDP command to the target's session" do
      page.go_to("/simple")

      result = target_of(page).command("Runtime.evaluate", expression: "document.title")

      expect(result.dig("result", "value")).to eq("Test")
    end
  end
end
