# frozen_string_literal: true

describe Ferrum::Context do
  describe "#add_target" do
    let(:context) { browser.contexts.create }
    let(:params) { { "targetId" => "iframe-target", "type" => "iframe", "url" => "" } }

    it "replaces the frame owner's session with the attached one" do
      context.add_target(params: params, session_id: "owner-session")
      target = context.add_target(params: params, session_id: "iframe-session", attached: true)

      expect(target.session_id).to eq("iframe-session")
    end

    it "keeps the attached session when the frame owner's comes later" do
      context.add_target(params: params, session_id: "iframe-session", attached: true)
      target = context.add_target(params: params, session_id: "owner-session")

      expect(target.session_id).to eq("iframe-session")
    end
  end
end
