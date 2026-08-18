# frozen_string_literal: true

module Ferrum
  class Downloads
    VALID_BEHAVIOR = %i[deny allow allowAndName default].freeze

    def initialize(page)
      @page = page
      @event = Utils::Event.new.tap(&:set)
      @files = {}
    end

    #
    # Returns information about all downloaded files.
    #
    # @return [Array<Hash>]
    #
    def files
      @files.values
    end

    #
    # Waits until the current download finishes.
    #
    # @param [Integer] timeout
    #   How long to wait in seconds.
    #
    # @yield
    #   Optional block that triggers the download, e.g. clicking a link.
    #
    # @return [void]
    #
    def wait(timeout = 5)
      @event.reset
      yield if block_given?
      @event.wait(timeout)
      @event.set
    end

    #
    # Sets the browser's download behavior and destination directory.
    #
    # @param [String] save_path
    #   Absolute path to the directory downloads should be saved to.
    #
    # @param [:deny, :allow, :allowAndName, :default] behavior
    #   Whether/how to allow downloads.
    #
    # @return [void]
    #
    # @raise [ArgumentError]
    # @raise [Ferrum::Error]
    #
    def set_behavior(save_path:, behavior: :allow)
      raise ArgumentError unless VALID_BEHAVIOR.include?(behavior.to_sym)
      raise Error, "supply absolute path for `:save_path` option" unless Pathname.new(save_path.to_s).absolute?

      @page.command("Browser.setDownloadBehavior",
                    browserContextId: @page.context_id,
                    downloadPath: save_path,
                    behavior: behavior,
                    eventsEnabled: true)
    end

    #
    # Subscribes to download related CDP events.
    #
    # @return [void]
    #
    def subscribe
      subscribe_download_will_begin
      subscribe_download_progress
    end

    #
    # Subscribes to the `Browser.downloadWillBegin` event to track new downloads.
    #
    # @return [void]
    #
    def subscribe_download_will_begin
      @page.on("Browser.downloadWillBegin") do |params|
        @event.reset
        @files[params["guid"]] = params
      end
    end

    #
    # Subscribes to the `Browser.downloadProgress` event to track download state.
    #
    # @return [void]
    #
    def subscribe_download_progress
      @page.on("Browser.downloadProgress") do |params|
        @files[params["guid"]].merge!(params)

        case params["state"]
        when "completed", "canceled"
          @event.set
        else
          @event.reset
        end
      end
    end
  end
end
