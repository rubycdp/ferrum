# frozen_string_literal: true

describe Ferrum::RemoteObject do
  describe "#value" do
    it "serializes the handle into a Ruby value" do
      handle = browser.evaluate_handle("({ list: [1, 'a'], flag: true })")

      expect(handle.value).to eq("list" => [1, "a"], "flag" => true)
    end

    it "resolves nodes into Node objects" do
      browser.go_to("/index")
      handle = browser.evaluate_handle("Array.from(document.querySelectorAll('a'))")

      expect(handle.value).to eq(browser.css("a"))
    end
  end

  describe "#release" do
    it "makes the handle unusable" do
      handle = browser.evaluate_handle("({ a: 1 })")

      expect(handle.release).to be_nil
      expect { handle.value }.to raise_error(Ferrum::BrowserError)
    end

    it "returns nil when the handle is already released" do
      handle = browser.evaluate_handle("({ a: 1 })")
      handle.release

      expect(handle.release).to be_nil
    end
  end
end
