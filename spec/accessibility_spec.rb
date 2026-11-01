# frozen_string_literal: true

describe Ferrum::Accessibility do
  describe "#node_for" do
    before { browser.go_to("/accessibility") }

    it "returns the AXNode for a DOM node" do
      ax = browser.page.accessibility.node_for(browser.at_css("#submit"))

      expect(ax).to be_a(Ferrum::Accessibility::AXNode)
      expect(ax.role).to eq("button")
      expect(ax.name).to eq("Send form")
      expect(ax.description).to eq("Sends the form to the server")
      expect(ax.properties).to include("focusable" => true, "describedby" => "hint")
    end

    it "returns nil for an ignored element" do
      expect(browser.page.accessibility.node_for(browser.at_css("#hidden"))).to be_nil
    end
  end

  describe "#partial_tree" do
    before { browser.go_to("/accessibility") }

    it "returns an array of AXNodes" do
      nodes = browser.page.accessibility.partial_tree(node: browser.at_css("#submit"))

      expect(nodes).to all(be_a(Ferrum::Accessibility::AXNode))
      expect(nodes.map(&:role)).to include("button")
    end

    it "returns AXNodes for a node in an iframe" do
      browser.go_to("/accessibility_iframe")
      frame_node = browser.page.at_css("iframe").frame.at_css("#child_btn")

      nodes = browser.page.accessibility.partial_tree(node: frame_node)

      expect(nodes).to all(be_a(Ferrum::Accessibility::AXNode))
      expect(nodes).not_to be_empty
      expect(nodes.map(&:role)).to include("button")
      expect(nodes.map(&:name)).to include("Frame button")
    end
  end

  describe "#snapshot" do
    before { browser.go_to("/accessibility") }

    it "returns the full tree as AXNodes including a button" do
      nodes = browser.page.accessibility.snapshot

      expect(nodes).to all(be_a(Ferrum::Accessibility::AXNode))
      expect(nodes.map(&:role)).to include("button")
    end
  end

  describe "#query" do
    before { browser.go_to("/accessibility") }

    it "finds nodes by accessible name" do
      nodes = browser.page.accessibility.query(name: "Send form")

      expect(nodes.map(&:name)).to include("Send form")
    end

    it "scopes the query to a node's subtree — inside node is found" do
      scope = browser.at_css("#scope")
      nodes = browser.page.accessibility.query(name: "Inside only", node: scope)

      expect(nodes.map(&:name)).to include("Inside only")
    end

    it "scopes the query to a node's subtree — outside sibling is absent" do
      scope = browser.at_css("#scope")
      nodes = browser.page.accessibility.query(name: "Outside only", node: scope)

      expect(nodes).to be_empty
    end

    it "scopes the query to a node in an iframe" do
      browser.go_to("/accessibility_iframe")
      frame_node = browser.page.at_css("iframe").frame.at_css("#child_btn")

      nodes = browser.page.accessibility.query(name: "Frame button", node: frame_node)

      expect(nodes).not_to be_empty
      expect(nodes.map(&:name)).to include("Frame button")
    end
  end

  describe "#root" do
    before { browser.go_to("/accessibility") }

    it "returns a single root AXNode" do
      expect(browser.page.accessibility.root).to be_a(Ferrum::Accessibility::AXNode)
    end
  end
end
