# frozen_string_literal: true

require "ferrum/frame"

module Ferrum
  class Page
    module Frames
      attr_reader :main_frame

      def frames
        @frames.values
      end

      def frame_by(id: nil, name: nil)
        if id
          @frames[id]
        elsif name
          frames.find { |f| f.name == name }
        else
          raise ArgumentError
        end
      end

      def frames_subscribe
        on("Page.frameAttached") do |params|
          parent_frame_id, frame_id = params.values_at("parentFrameId", "frameId")
          @frames[frame_id] = Frame.new(frame_id, self, parent_frame_id)
        end

        on("Page.frameStartedLoading") do |params|
          frame = @frames[params["frameId"]]
          frame.state = :started_loading
          @event.reset
        end

        on("Page.frameNavigated") do |params|
          frame_id, name = params["frame"]&.values_at("id", "name")
          frame = @frames[frame_id]
          frame.state = :navigated
          frame.name = name unless name.to_s.empty?
        end

        on("Page.frameStoppedLoading") do |params|
          # `DOM.performSearch` doesn't work without getting #document node first.
          # It returns node with nodeId 1 and nodeType 9 from which descend the
          # tree and we save it in a variable because if we call that again root
          # node will change the id and all subsequent nodes have to change id too.
          if @main_frame.id == params["frameId"]
            @event.set if idling?
            get_document_id
          end

          frame = @frames[params["frameId"]]
          frame.state = :stopped_loading

          @event.set if idling?
        end

        on("Page.navigatedWithinDocument") do
          @event.set if idling?
        end

        on("Network.requestWillBeSent") do |params|
          if params["frameId"] == @main_frame.id
            # Possible types:
            # Document, Stylesheet, Image, Media, Font, Script, TextTrack, XHR,
            # Fetch, EventSource, WebSocket, Manifest, SignedExchange, Ping,
            # CSPViolationReport, Other
            @event.reset if params["type"] == "Document"
          end
        end

        on("Runtime.executionContextCreated") do |params|
          context_id = params.dig("context", "id")
          frame_id = params.dig("context", "auxData", "frameId")
          frame = @frames[frame_id] || Frame.new(frame_id, self)
          frame.execution_id = context_id

          @main_frame ||= frame
          @frames[frame_id] ||= frame
        end

        on("Runtime.executionContextDestroyed") do |params|
          execution_id = params["executionContextId"]
          frame = frames.find { |f| f.execution_id?(execution_id) }
          frame.execution_id = nil
        end

        on("Runtime.executionContextsCleared") do
          @frames.delete_if { |_, f| !f.main? }
        end
      end

      private

      def idling?
        @frames.all? { |_, f| f.state == :stopped_loading }
      end
    end
  end
end
