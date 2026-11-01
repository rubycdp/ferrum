# frozen_string_literal: true

require "ferrum/accessibility/ax_node"

describe Ferrum::Accessibility::AXNode do
  let(:params) do
    {
      "nodeId" => "7",
      "ignored" => false,
      "role" => { "type" => "role", "value" => "button" },
      "name" => { "type" => "computedString", "value" => "Send form" },
      "description" => { "type" => "computedString", "value" => "Sends the form" },
      "value" => { "type" => "computedString", "value" => "Go" },
      "properties" => [
        { "name" => "focusable", "value" => { "type" => "booleanOrUndefined", "value" => true } },
        { "name" => "required", "value" => { "type" => "booleanOrUndefined", "value" => true } }
      ],
      "childIds" => %w[8 9],
      "backendDOMNodeId" => 42
    }
  end

  subject(:ax_node) { described_class.new(params) }

  let(:bare_node) { described_class.new({ "nodeId" => "1", "ignored" => true }) }

  describe "#role" do
    it "returns the role" do
      expect(ax_node.role).to eq("button")
    end

    it "returns nil without a role" do
      expect(bare_node.role).to be_nil
    end
  end

  describe "#name" do
    it "returns the name" do
      expect(ax_node.name).to eq("Send form")
    end

    it "returns nil without a name" do
      expect(bare_node.name).to be_nil
    end
  end

  describe "#description" do
    it "returns the description" do
      expect(ax_node.description).to eq("Sends the form")
    end

    it "returns nil without a description" do
      expect(bare_node.description).to be_nil
    end
  end

  describe "#value" do
    it "returns the value" do
      expect(ax_node.value).to eq("Go")
    end

    it "returns nil without a value" do
      expect(bare_node.value).to be_nil
    end
  end

  describe "#properties" do
    it "flattens properties into a name => value hash" do
      expect(ax_node.properties).to eq("focusable" => true, "required" => true)
    end

    it "returns an empty hash without properties" do
      expect(bare_node.properties).to eq({})
    end

    it "returns a frozen hash" do
      expect { ax_node.properties["focusable"] = false }.to raise_error(FrozenError)
    end
  end

  describe "#ignored?" do
    it "returns whether the node is ignored" do
      expect(ax_node.ignored?).to be(false)
      expect(bare_node.ignored?).to be(true)
    end
  end

  describe "#ignored_reasons" do
    it "returns nil without ignored reasons" do
      expect(bare_node.ignored_reasons).to be_nil
    end
  end

  describe "#node_id" do
    it "returns the node id" do
      expect(ax_node.node_id).to eq("7")
    end
  end

  describe "#backend_dom_node_id" do
    it "returns the backend DOM node id" do
      expect(ax_node.backend_dom_node_id).to eq(42)
    end
  end

  describe "#child_ids" do
    it "returns the child ids" do
      expect(ax_node.child_ids).to eq(%w[8 9])
    end

    it "returns a frozen array" do
      expect { ax_node.child_ids << "x" }.to raise_error(FrozenError)
    end
  end

  describe "#to_h" do
    it "returns the params" do
      expect(ax_node.to_h).to eq(params)
    end

    it "returns a deeply frozen hash" do
      expect { ax_node.to_h["properties"] << {} }.to raise_error(FrozenError)
    end

    it "freezes hash keys, not just values" do
      key = ax_node.to_h.keys.find { |k| k == "nodeId" }
      expect(key).not_to be_nil
      expect(key).to be_frozen
    end
  end
end
