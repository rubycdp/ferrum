# frozen_string_literal: true

module Ferrum
  class Page
    module Frame
      def execution_context_id
        context_id = current_execution_context_id
        raise NoExecutionContextError unless context_id
        context_id
      rescue NoExecutionContextError
        @event.reset
        @event.wait(timeout) ? retry : raise
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
        when :parent
          @frame_stack.pop
        when :top
          @frame_stack = []
        else
          @frame_stack << handle
          inject_extensions
        end
      end

      private

      def subscribe
        super if defined?(super)

        @client.on("Page.frameAttached") do |params|
          @frames[params["frameId"]] = { "parent_id" => params["parentFrameId"] }
        end

        @client.on("Page.frameStartedLoading") do |params|
          @waiting_frames << params["frameId"]
          @event.reset
        end

        @client.on("Page.frameNavigated") do |params|
          id = params["frame"]["id"]
          if frame = @frames[id]
            frame.merge!(params["frame"].select { |k, v| k == "name" || k == "url" })
          end
        end

        @client.on("Page.frameScheduledNavigation") do |params|
          @waiting_frames << params["frameId"]
          @event.reset
        end

        @client.on("Page.frameStoppedLoading") do |params|
          # `DOM.performSearch` doesn't work without getting #document node first.
          # It returns node with nodeId 1 and nodeType 9 from which descend the
          # tree and we save it in a variable because if we call that again root
          # node will change the id and all subsequent nodes have to change id too.
          if params["frameId"] == @frame_id
            @event.set if @waiting_frames.empty?
            @document_id = get_document_id
          end

          if @waiting_frames.include?(params["frameId"])
            @waiting_frames.delete(params["frameId"])
            @event.set if @waiting_frames.empty?
          end
        end

        @client.on("Runtime.executionContextCreated") do |params|
          context_id = params.dig("context", "id")
          @execution_context_id ||= context_id

          frame_id = params.dig("context", "auxData", "frameId")
          @frame_id ||= frame_id # Remember the very first frame since it's the main one

          if @frames[frame_id]
            @frames[frame_id].merge!("execution_context_id" => context_id)
          else
            @frames[frame_id] = { "execution_context_id" => context_id }
          end
        end

        @client.on("Runtime.executionContextDestroyed") do |params|
          context_id = params["executionContextId"]

          if @execution_context_id == context_id
            @execution_context_id = nil
          end

          _id, frame = @frames.find { |_, p| p["execution_context_id"] == context_id }
          frame["execution_context_id"] = nil if frame
        end

        @client.on("Runtime.executionContextsCleared") do
          # If we didn't have time to set context id at the beginning we have
          # to set lock and release it when we set something.
          @execution_context_id = nil
        end
      end

      def current_execution_context_id
        if @frame_stack.empty?
          @execution_context_id
        else
          @frames.dig(@frame_stack.last, "execution_context_id")
        end
      end
    end
  end
end
