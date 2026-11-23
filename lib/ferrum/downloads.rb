# frozen_string_literal: true

module Ferrum
  #
  # Tracks files downloaded by a page. Configures the browser's download
  # behavior/destination via {#set_behavior}, subscribes to the
  # `Browser.downloadWillBegin`/`Browser.downloadProgress` CDP events to
  # record their progress in {#files}, and lets callers block until the
  # current download finishes via {#wait}.
  #
  class Downloads
    WAIT_TIMEOUT = 5
    WAIT_DEPRECATED = "downloads.wait will be removed in Ferrum 0.22. Use page.await_download { ... } around the " \
                      "code that starts the download."
    VALID_BEHAVIOR = %i[deny allow allowAndName default].freeze

    def initialize(page)
      @page = page
      @idle = Concurrency::Cell.set(true)
      @files = {}
      @waiters = []
      @waiters_mutex = Mutex.new
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
    # Runs the block and waits for the download it starts to finish.
    #
    # @param [Numeric, Deadline] timeout
    #   How long the block and the download may take together, in seconds.
    #
    # @yield The code that starts the download, e.g. clicking a link.
    #
    # @return [Hash, nil]
    #   The finished download, like an entry of {#files}, its `"state"` is
    #   `"completed"` or `"canceled"`. `nil` if it doesn't finish in time.
    #
    # @raise [ArgumentError]
    #   If no block is given.
    #
    # @example
    #   page.await_download { page.at_css("#download").click } # => {"suggestedFilename" => "file.pdf", ...}
    #
    def await_download(timeout: WAIT_TIMEOUT)
      raise ArgumentError, "await_download needs a block that starts the download" unless block_given?

      deadline = Deadline.wrap(timeout)
      waiter = { guid: nil, cell: Concurrency::Cell.new }
      @waiters_mutex.synchronize { @waiters << waiter }
      yield
      waiter[:cell].value if waiter[:cell].wait(deadline)
    ensure
      @waiters_mutex.synchronize { @waiters.delete(waiter) }
    end

    #
    # Same as {#await_download}, but raises if the download doesn't finish in time.
    #
    # @param [Numeric, Deadline] timeout
    #
    # @yield The code that starts the download.
    #
    # @return [Hash]
    #
    # @raise [TimeoutError]
    #   If the download doesn't finish in time.
    #
    # @raise [ArgumentError]
    #   If no block is given.
    #
    def await_download!(timeout: WAIT_TIMEOUT, &)
      await_download(timeout: timeout, &) || raise(TimeoutError)
    end

    #
    # Waits until the current download finishes.
    #
    # @deprecated Will be removed in Ferrum 0.22. Use {#await_download} around the code that starts the download.
    #
    # @param [Numeric, Deadline] timeout
    #   How long to wait in seconds.
    #
    # @yield
    #   Optional block that triggers the download, e.g. clicking a link.
    #
    # @return [void]
    #
    def wait(timeout = WAIT_TIMEOUT)
      Utils::Deprecate.warn(WAIT_DEPRECATED, user_code: true)
      deadline = Deadline.wrap(timeout)
      generation = @idle.clear
      yield if block_given?
      @idle.wait(deadline)
      @idle.set(true) if generation == @idle.generation
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
    # @raise [TimeoutError]
    #
    def set_behavior(save_path:, behavior: :allow)
      raise ArgumentError unless VALID_BEHAVIOR.include?(behavior.to_sym)
      raise Error, "supply absolute path for `:save_path` option" unless Pathname.new(save_path.to_s).absolute?

      options = { browserContextId: @page.context_id } if @page.context_id
      @page.command("Browser.setDownloadBehavior",
                    **Hash(options),
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
        @idle.clear
        @files[params["guid"]] = params
        @waiters_mutex.synchronize { @waiters.find { |w| w[:guid].nil? }&.store(:guid, params["guid"]) }
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
          @idle.set(true)
          finish_waiters(params["guid"])
        else
          @idle.clear
        end
      end
    end

    private

    def finish_waiters(guid)
      waiters = @waiters_mutex.synchronize { @waiters.select { |w| w[:guid] == guid } }
      waiters.each { |w| w[:cell].set(@files[guid]) }
    end
  end
end
