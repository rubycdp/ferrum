# frozen_string_literal: true

require "ferrum/frame"

module Ferrum
  class Page
    module Frames
      attr_reader :main_frame

      def frames
        @frames.values
      end

      def frame_by(id: nil, name: nil, execution_id: nil)
        if id
          @frames[id]
        elsif name
          frames.find { |f| f.name == name }
        elsif execution_id
          frames.find { |f| f.execution_id == execution_id }
        else
          raise ArgumentError
        end
      end

      def frames_subscribe
        subscribe_frame_attached
        subscribe_frame_started_loading
        subscribe_frame_navigated
        subscribe_frame_stopped_loading

        subscribe_navigated_within_document

        subscribe_request_will_be_sent

        subscribe_execution_context_created
        subscribe_execution_context_destroyed
        subscribe_execution_contexts_cleared
      end

      private

      def subscribe_frame_attached
        on("Page.frameAttached") do |params|
          parent_frame_id, frame_id = params.values_at("parentFrameId", "frameId")
          @frames[frame_id] = Frame.new(frame_id, self, parent_frame_id)
        end
      end

      def subscribe_frame_started_loading
        on("Page.frameStartedLoading") do |params|
          frame = @frames[params["frameId"]]
          frame.state = :started_loading
          @event.reset
        end
      end

      def subscribe_frame_navigated
        on("Page.frameNavigated") do |params|
          frame_id, name = params["frame"]&.values_at("id", "name")
          frame = @frames[frame_id]
          frame.state = :navigated
          frame.name = name unless name.to_s.empty?
        end
      end

      def subscribe_frame_stopped_loading
        on("Page.frameStoppedLoading") do |params|
          # `DOM.performSearch` doesn't work without getting #document node first.
          # It returns node with nodeId 1 and nodeType 9 from which descend the
          # tree and we save it in a variable because if we call that again root
          # node will change the id and all subsequent nodes have to change id too.
          if @main_frame.id == params["frameId"]
            @event.set if idling?
            document_node_id
          end

          frame = @frames[params["frameId"]]
          frame.state = :stopped_loading

          @event.set if idling?
        end
      end

      def subscribe_navigated_within_document
        on("Page.navigatedWithinDocument") do
          @event.set if idling?
        end
      end

      def subscribe_request_will_be_sent
        on("Network.requestWillBeSent") do |params|
          # Possible types:
          # Document, Stylesheet, Image, Media, Font, Script, TextTrack, XHR,
          # Fetch, EventSource, WebSocket, Manifest, SignedExchange, Ping,
          # CSPViolationReport, Other
          @event.reset if params["frameId"] == @main_frame.id && params["type"] == "Document"
        end
      end

      def subscribe_execution_context_created
        on("Runtime.executionContextCreated") do |params|
          context_id = params.dig("context", "id")
          frame_id = params.dig("context", "auxData", "frameId")

          unless @main_frame.id
            root_frame = command("Page.getFrameTree").dig("frameTree", "frame", "id")
            if frame_id == root_frame
              @main_frame.id = frame_id
              @frames[frame_id] = @main_frame
            end
          end

          frame = @frames[frame_id] || Frame.new(frame_id, self)
          frame.execution_id = context_id

          @frames[frame_id] ||= frame
        end
      end

      def subscribe_execution_context_destroyed
        on("Runtime.executionContextDestroyed") do |params|
          execution_id = params["executionContextId"]
          frame = frame_by(execution_id: execution_id)
          frame&.execution_id = nil
        end
      end

      def subscribe_execution_contexts_cleared
        on("Runtime.executionContextsCleared") do
          @frames.delete_if { |_, f| !f.main? }
          @main_frame.execution_id = nil
        end
      end

      def idling?
        @frames.all? { |_, f| f.state == :stopped_loading }
      end
    end
  end
end
