# frozen_string_literal: true

module Ferrum
  class Page
    module Frame
      attr_reader :frame_id

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

      def within_frame(frame)
        unless frame.is_a?(Node)
          raise ArgumentError, "Node is expected, but #{frame.class} is given"
        end

        frame_id = frame.description["frameId"]
        @frame_stack << frame_id
        inject_extensions
        yield
      ensure
        @frame_stack.pop
      end

      private

      def subscribe
        super if defined?(super)

        on("Page.frameAttached") do |params|
          @frames[params["frameId"]] = { "parent_id" => params["parentFrameId"] }
        end

        on("Page.frameStartedLoading") do |params|
          @waiting_frames << params["frameId"]
          @event.reset
        end

        on("Page.frameNavigated") do |params|
          id = params["frame"]["id"]
          if frame = @frames[id]
            frame.merge!(params["frame"].select { |k, _| k == "name" || k == "url" })
          end
        end

        on("Page.frameScheduledNavigation") do |params|
          @waiting_frames << params["frameId"]
          @event.reset
        end

        on("Page.navigatedWithinDocument") do
          if @waiting_frames.include?(params["frameId"])
            @waiting_frames.delete(params["frameId"])
            @event.set if @waiting_frames.empty?
          end
        end

        on("Page.frameStoppedLoading") do |params|
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

        on("Network.requestWillBeSent") do |params|
          if params["frameId"] == @frame_id
            # Possible types:
            # Document, Stylesheet, Image, Media, Font, Script, TextTrack, XHR,
            # Fetch, EventSource, WebSocket, Manifest, SignedExchange, Ping,
            # CSPViolationReport, Other
            @event.reset if params["type"] == "Document"
          end
        end

        on("Runtime.executionContextCreated") do |params|
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

        on("Runtime.executionContextDestroyed") do |params|
          context_id = params["executionContextId"]

          if @execution_context_id == context_id
            @execution_context_id = nil
          end

          _id, frame = @frames.find { |_, p| p["execution_context_id"] == context_id }
          frame["execution_context_id"] = nil if frame
        end

        on("Runtime.executionContextsCleared") do
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
