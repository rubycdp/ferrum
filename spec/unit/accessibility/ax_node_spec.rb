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

  it "exposes role, name, description and value" do
    expect(ax_node.role).to eq("button")
    expect(ax_node.name).to eq("Send form")
    expect(ax_node.description).to eq("Sends the form")
    expect(ax_node.value).to eq("Go")
  end

  it "flattens properties into a name => value hash" do
    expect(ax_node.properties).to eq("focusable" => true, "required" => true)
  end

  it "exposes identity and tree fields" do
    expect(ax_node.node_id).to eq("7")
    expect(ax_node.backend_dom_node_id).to eq(42)
    expect(ax_node.child_ids).to eq(%w[8 9])
    expect(ax_node.ignored?).to be(false)
    expect(ax_node.to_h).to eq(params)
  end

  it "tolerates missing keys" do
    node = described_class.new({ "nodeId" => "1", "ignored" => true })
    expect(node.role).to be_nil
    expect(node.name).to be_nil
    expect(node.description).to be_nil
    expect(node.value).to be_nil
    expect(node.properties).to eq({})
    expect(node.ignored?).to be(true)
    expect(node.ignored_reasons).to be_nil
  end

  describe "immutability (deep freeze)" do
    let(:mutable_params) do
      {
        "nodeId" => "10",
        "ignored" => false,
        "role" => { "type" => "role", "value" => "slider" },
        "childIds" => %w[11 12],
        "properties" => [
          { "name" => "focusable", "value" => { "type" => "booleanOrUndefined", "value" => true } }
        ]
      }
    end

    subject(:frozen_node) { described_class.new(mutable_params) }

    it "raises FrozenError when mutating child_ids" do
      expect { frozen_node.child_ids << "x" }.to raise_error(FrozenError)
    end

    it "raises FrozenError when mutating the properties array from to_h" do
      expect { frozen_node.to_h["properties"] << {} }.to raise_error(FrozenError)
    end

    it "freezes hash keys, not just values" do
      key = frozen_node.to_h.keys.find { |k| k == "nodeId" }
      expect(key).not_to be_nil
      expect(key).to be_frozen
    end

    it "raises FrozenError when mutating the memoized properties hash" do
      expect { frozen_node.properties["focusable"] = false }.to raise_error(FrozenError)
    end
  end
end
