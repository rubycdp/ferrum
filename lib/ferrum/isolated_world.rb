# frozen_string_literal: true

module Ferrum
  #
  # A named JavaScript world in a {Frame}: it shares the frame's DOM but has
  # its own globals, so the page's scripts can't see or tamper with what runs
  # in it. Chrome creates the world on first use and again in every new
  # document, and it's the same world that
  # {Page#evaluate_on_new_document} with `world_name:` runs scripts in.
  # Evaluation methods are the same as {Frame}'s, see {Frame::Runtime}.
  #
  class IsolatedWorld
    include Frame::Runtime

    # The world's name.
    #
    # @return [String]
    attr_reader :name

    # The frame the world belongs to.
    #
    # @return [Frame]
    attr_reader :frame

    # The page the world belongs to.
    #
    # @return [Page]
    attr_reader :page

    def initialize(frame, name)
      @frame = frame
      @page = frame.page
      @name = name
      @execution_id = Concurrent::MVar.new
    end

    #
    # Execution context id of the world in the frame's current document,
    # creating the world there if it doesn't exist yet.
    #
    # @return [Integer]
    #
    def execution_id!
      execution_id || begin
        id = @page.command("Page.createIsolatedWorld", frameId: @frame.id, worldName: @name)["executionContextId"]
        self.execution_id = id
        execution_id || id
      end
    end

    #
    # Execution context id of the world in the frame's current document.
    #
    # @return [Integer, nil]
    #
    def execution_id
      value = @execution_id.value
      return if value.instance_of?(Object)

      value
    end

    #
    # Sets the execution context id, or clears it if +nil+ is given, e.g.
    # when the document the world was created in is gone.
    #
    # @param [Integer, nil] value
    #
    # @return [Integer, nil]
    #
    def execution_id=(value)
      if value.nil?
        @execution_id.try_take!
      else
        @execution_id.try_put!(value)
      end
    end

    #
    # Debug representation of the world.
    #
    # @return [String]
    #
    def inspect
      "#<#{self.class} @name=#{@name.inspect} @frame_id=#{@frame.id.inspect} @execution_id=#{execution_id.inspect}>"
    end

    private

    def resolve_node_options
      { executionContextId: execution_id! }
    end
  end
end
