# frozen_string_literal: true

describe Ferrum::Target do
  describe "#worker" do
    it "raises for a service worker that isn't attached" do
      page.go_to
      page.execute(%(await navigator.serviceWorker.register("/sw.js")), timeout: 5)
      target = wait_for_target(&:service_worker?)
      wait_for { target.session_id }.to be_nil

      expect { target.worker }.to raise_error(Ferrum::NoSuchTargetError, /attach_target/)
    end
  end
end
