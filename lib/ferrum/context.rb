# frozen_string_literal: true

require "ferrum/target"

module Ferrum
  class Context
    POSITION = %i[first last].freeze

    attr_reader :id, :targets

    def initialize(client, contexts, id)
      @id = id
      @client = client
      @contexts = contexts
      @targets = Concurrent::Map.new
      @pendings = Concurrent::MVar.new
    end

    def default_target
      @default_target ||= create_target
    end

    def page
      default_target.page
    end

    def pages
      @targets.values.map(&:page)
    end

    # When we call `page` method on target it triggers ruby to connect to given
    # page by WebSocket, if there are many opened windows but we need only one
    # it makes more sense to get and connect to the needed one only which
    # usually is the last one.
    def windows(pos = nil, size = 1)
      raise ArgumentError if pos && !POSITION.include?(pos)

      windows = @targets.values.select(&:window?)
      windows = windows.send(pos, size) if pos
      windows.map(&:page)
    end

    def create_page(**options)
      target = create_target
      target.page = target.build_page(**options)
    end

    def create_target
      @client.command("Target.createTarget", browserContextId: @id, url: "about:blank")
      target = @pendings.take(@client.timeout)
      raise NoSuchTargetError unless target.is_a?(Target)

      target
    end

    def add_target(params:, session_id: nil)
      new_target = Target.new(@client, session_id, params)
      target = @targets.put_if_absent(new_target.id, new_target)
      target ||= new_target # `put_if_absent` returns nil if added a new value or existing if there was one already
      @pendings.put(target, @client.timeout) if @pendings.empty?
      target
    end

    def update_target(target_id, params)
      @targets[target_id]&.update(params)
    end

    def delete_target(target_id)
      @targets.delete(target_id)
    end

    def close_targets_connection
      @targets.each_value do |target|
        next unless target.connected?

        target.page.close_connection
      end
    end

    def dispose
      @contexts.dispose(@id)
    end

    def target?(target_id)
      !!@targets[target_id]
    end

    def inspect
      %(#<#{self.class} @id=#{@id.inspect} @targets=#{@targets.inspect} @default_target=#{@default_target.inspect}>)
    end
  end
end
