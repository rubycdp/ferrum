module Ferrum
  class Browser
    module Frame
      def execution_context_id
        @mutex.synchronize do
          if !@frame_stack.empty?
            @frames[@frame_stack.last]["execution_context_id"]
          else
            @execution_context_id
          end
        end
      end

      def frame_name
        evaluate("window.name")
      end

      def frame_url
        evaluate("window.location.href")
      end

      def frame_title
        evaluate("document.title")
      end

      def switch_to_frame(handle)
        case handle
        when Capybara::Node::Base
          @frame_stack << handle.native.node["frameId"]
          inject_extensions
        when :parent
          @frame_stack.pop
        when :top
          @frame_stack = []
        end
      end

      private

      def subscribe_events
        super if defined?(super)

        @client.subscribe("Page.frameAttached") do |params|
          @frames[params["frameId"]] = { "parent_id" => params["parentFrameId"] }
        end

        @client.subscribe("Page.frameStartedLoading") do |params|
          @waiting_frames << params["frameId"]
          @mutex.try_lock
        end

        @client.subscribe("Page.frameNavigated") do |params|
          id = params["frame"]["id"]
          if frame = @frames[id]
            frame.merge!(params["frame"].select { |k, v| k == "name" || k == "url" })
          end
        end

        @client.subscribe("Page.frameScheduledNavigation") do |params|
          # Trying to lock mutex if frame is the main frame
          @waiting_frames << params["frameId"]
          @mutex.try_lock
        end

        @client.subscribe("Page.frameStoppedLoading") do |params|
          # `DOM.performSearch` doesn't work without getting #document node first.
          # It returns node with nodeId 1 and nodeType 9 from which descend the
          # tree and we save it in a variable because if we call that again root
          # node will change the id and all subsequent nodes have to change id too.
          # `command` is not allowed in the block as it will deadlock the process.
          if params["frameId"] == @frame_id
            signal if @waiting_frames.empty?
            @client.command("DOM.getDocument", depth: 0)
          end

          if @waiting_frames.include?(params["frameId"])
            @waiting_frames.delete(params["frameId"])
            signal if @waiting_frames.empty?
          end
        end

        @client.subscribe("Runtime.executionContextCreated") do |params|
          frame_id = params.dig("context", "auxData", "frameId")
          execution_context_id = params.dig("context", "id")

          # Remember the very first frame since it's the main one
          @frame_id ||= frame_id
          @execution_context_id ||= execution_context_id

          if @frames[frame_id]
            @frames[frame_id].merge!("execution_context_id" => execution_context_id)
          else
            @frames[frame_id] = { "execution_context_id" => execution_context_id }
          end
        end

        @client.subscribe("Runtime.executionContextDestroyed") do |params|
          execution_context_id = params["executionContextId"]
          id, frame = @frames.find { |_, p| p["execution_context_id"] == execution_context_id }
          frame["execution_context_id"] = nil if frame

          if @execution_context_id == execution_context_id
            @execution_context_id = nil
          end
        end

        @client.subscribe("Runtime.executionContextsCleared") do
          # If we didn't have time to set context id at the beginning we have
          # to set lock and release it when we set something.
          @execution_context_id = nil
        end
      end
    end
  end
end
