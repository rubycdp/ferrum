# frozen_string_literal: true

describe Ferrum::IsolatedWorld do
  it "evaluates apart from the page's globals but shares its DOM" do
    page.go_to("/simple")
    world = page.isolated_world("ferrum")

    world.execute("window.secret = 'isolated'")

    expect(world.evaluate("window.secret")).to eq("isolated")
    expect(world.evaluate("document.title")).to eq("Test")
    expect(page.evaluate("window.secret")).to be_nil
  end

  it "reaches the world of a script added with evaluate_on_new_document" do
    page.evaluate_on_new_document("window.secret = 'isolated'", world_name: "ferrum")
    page.go_to("/simple")

    expect(page.isolated_world("ferrum").evaluate("window.secret")).to eq("isolated")
    expect(page.evaluate("window.secret")).to be_nil
  end

  it "starts over in a new document" do
    page.go_to("/simple")
    world = page.isolated_world("ferrum")
    world.execute("window.secret = 'isolated'")

    page.go_to("/simple")

    expect(world.evaluate("window.secret")).to be_nil
    expect(world.evaluate("document.title")).to eq("Test")
  end

  it "takes and returns nodes" do
    page.go_to("/simple")
    world = page.isolated_world("ferrum")

    expect(world.evaluate("arguments[0].id", page.at_css("#break"))).to eq("break")
    expect(world.evaluate("document.querySelector('#nav')").text).to eq("Home")
  end

  it "takes named arguments and evaluates on its nodes" do
    page.go_to("/simple")
    world = page.isolated_world("ferrum")
    world.execute("window.secret = 'isolated'")

    node = world.evaluate("document.querySelector('#nav')")

    expect(world.evaluate("el.id", el: page.at_css("#break"))).to eq("break")
    expect(node.evaluate("this.textContent + window.secret")).to eq("Homeisolated")
  end

  it "evaluates in a frame" do
    page.go_to("/frames")
    frame = page.at_css("iframe[name]").frame

    expect(frame.isolated_world("ferrum").evaluate("location.pathname")).to eq("/slow")
  end
end
