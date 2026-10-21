# frozen_string_literal: true

describe Ferrum::Page::Frames do
  let(:client_class) do
    Class.new do
      attr_reader :options, :handlers, :navigation_events

      def initialize(navigation_events)
        @options = Ferrum::Browser::Options.new(timeout: 0.01, js_errors: false)
        @handlers = {}
        @navigation_events = navigation_events
      end

      def on(name, &block)
        callbacks = (handlers[name] ||= [])
        callbacks << block
        callbacks.index(block)
      end

      def command(name, **params)
        case name
        when "Page.getFrameTree"
          return { "frameTree" => { "frame" => { "id" => "main" } } }
        when "Runtime.enable"
          emit("Runtime.executionContextCreated",
               { "context" => { "id" => 1, "auxData" => { "frameId" => "main", "isDefault" => true } } })
        when "Input.dispatchMouseEvent"
          dispatch_mouse_event(params)
        end
        {}
      end

      private

      def dispatch_mouse_event(params)
        return unless params.fetch(:type) == "mouseReleased"

        navigation_events.each { |event, data| emit(event, data) }
      end

      def emit(name, params)
        callbacks = handlers.fetch(name, [])
        callbacks.each_with_index do |callback, index|
          callback.call(params, index, callbacks.length)
        end
      end
    end
  end
  let(:client) { client_class.new(navigation_events) }
  let(:page) { Ferrum::Page.new(client, context_id: "context", target_id: "main") }
  let(:navigation_events) do
    [
      ["Page.frameStartedLoading", { "frameId" => "main" }],
      ["Page.frameAttached", { "frameId" => "child", "parentFrameId" => "main" }],
      ["Page.frameStartedLoading", { "frameId" => "child" }],
      ["Page.frameStoppedLoading", { "frameId" => "main" }],
      ["Page.frameDetached", { "frameId" => "child", "reason" => "swap" }]
    ]
  end

  %w[swap remove].each do |reason|
    it "finishes a click when the last loading child detaches with reason #{reason}" do
      navigation_events.last.last["reason"] = reason

      expect(page.mouse.click(x: 1, y: 1)).to eq(page.mouse)
      expect(page.frames.map(&:id)).to eq(["main"])
    end
  end

  it "keeps waiting while another child is loading" do
    navigation_events.insert(-2,
                             ["Page.frameAttached", { "frameId" => "other", "parentFrameId" => "main" }],
                             ["Page.frameStartedLoading", { "frameId" => "other" }])

    expect { page.mouse.click(x: 1, y: 1) }.to raise_error(Ferrum::TimeoutError)
  end

  it "keeps waiting while the main document is loading" do
    navigation_events.reject! { |name, _params| name == "Page.frameStoppedLoading" }

    expect { page.mouse.click(x: 1, y: 1) }.to raise_error(Ferrum::TimeoutError)
  end

  it "keeps waiting after the main execution context is cleared" do
    navigation_events.insert(-2, ["Runtime.executionContextsCleared", {}])

    expect { page.mouse.click(x: 1, y: 1) }.to raise_error(Ferrum::TimeoutError)
  end

  it "does not complete a navigation when the main frame detaches" do
    navigation_events.replace([
      ["Page.frameStoppedLoading", { "frameId" => "main" }],
      ["Network.requestWillBeSent", { "frameId" => "main", "requestId" => "navigation",
                                      "loaderId" => "navigation", "type" => "Document",
                                      "request" => { "url" => "http://example.com/", "method" => "GET", "headers" => {} } }],
      ["Page.frameDetached", { "frameId" => "main", "reason" => "swap" }]
    ])

    expect { page.mouse.click(x: 1, y: 1) }.to raise_error(Ferrum::TimeoutError)
    expect(page.frames.map(&:id)).to eq(["main"])
    expect(page.main_frame.execution_id).to be_nil
  end
end
