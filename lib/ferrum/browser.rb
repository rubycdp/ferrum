# frozen_string_literal: true

require "base64"
require "forwardable"
require "ferrum/browser/targets"
require "ferrum/browser/process"
require "ferrum/browser/client"
require "ferrum/browser/page"

module Ferrum
  class Browser
    TIMEOUT = 5
    WINDOW_SIZE = [1024, 768].freeze
    EXTENSIONS = [
      File.expand_path("browser/javascripts/index.js", __dir__)
    ].freeze

    extend Forwardable

    attr_reader :headers, :window_size

    def self.start(*args)
      new(*args)
    end

    delegate subscribe: :@client
    delegate %i(window_handle window_handles switch_to_window open_new_window
                close_window within_window page) => :targets
    delegate %i(visit status_code body all_text property attributes attribute
                value visible? disabled? network_traffic clear_network_traffic
                path response_headers refresh click right_click double_click
                hover set click_coordinates drag drag_by select trigger
                scroll_to send_keys evaluate evaluate_on evaluate_async execute
                frame_url frame_title switch_to_frame current_url title go_back
                go_forward find_modal accept_confirm dismiss_confirm
                accept_prompt dismiss_prompt reset_modals authorize
                proxy_authorize) => :page

    attr_reader :process, :logger, :js_errors, :slowmo,
                :url_blacklist, :url_whitelist
    attr_writer :timeout

    def initialize(options = nil)
      options ||= {}

      @window_size = options.fetch(:window_size, WINDOW_SIZE)
      @original_window_size = @window_size

      @options = Hash(options.merge(window_size: @window_size))
      @logger, @timeout = @options.values_at(:logger, :timeout)
      @js_errors = @options.fetch(:js_errors, false)
      @slowmo = @options[:slowmo]

      self.url_blacklist = @options[:url_blacklist]
      self.url_whitelist = @options[:url_whitelist]

      if ENV["CUPRITE_DEBUG"] && !@logger
        STDOUT.sync = true
        @logger = STDOUT
        @options[:logger] = @logger
      end

      @options.freeze

      start
    end

    def extensions
      @extensions ||= begin
        exts = @options.fetch(:extensions, [])
        (EXTENSIONS + exts).map { |p| File.read(p) }
      end
    end

    def timeout
      @timeout || TIMEOUT
    end

    def source
      raise NotImplementedError
    end

    def parents(node)
      evaluate_on(node: node, expr: "_cuprite.parents(this)", by_value: false)
    end

    def find(method, selector)
      find_all(method, selector)
    end

    def find_within(node, method, selector)
      resolved = page.command("DOM.resolveNode", nodeId: node["nodeId"])
      object_id = resolved.dig("object", "objectId")
      find_all(method, selector, { "objectId" => object_id })
    end

    def visible_text(node)
      evaluate_on(node: node, expr: "_cuprite.visibleText(this)")
    end

    def delete_text(node)
      evaluate_on(node: node, expr: "_cuprite.deleteText(this)")
    end

    def select_file(node, value)
      page.command("DOM.setFileInputFiles", nodeId: node["nodeId"], files: Array(value))
    end

    def render(path, options = {})
      format = options.delete(:format)
      options = options.merge(path: path)
      bin = Base64.decode64(render_base64(format, options))
      File.open(path.to_s, "wb") { |f| f.write(bin) }
    end

    def render_base64(format, options = {})
      options = render_options(format, options)

      if options[:format].to_s == "pdf"
        options = {}
        options[:paperWidth] = @paper_size[:width].to_f if @paper_size
        options[:paperHeight] = @paper_size[:height].to_f if @paper_size
        options[:scale] = @zoom_factor if @zoom_factor
        page.command("Page.printToPDF", **options)
      else
        page.command("Page.captureScreenshot", **options)
      end.fetch("data")
    end

    def set_zoom_factor(zoom_factor)
      @zoom_factor = zoom_factor.to_f
    end

    def set_paper_size(size)
      @paper_size = size
    end

    def headers=(headers)
      @headers = {}
      add_headers(headers)
    end

    def add_headers(headers, permanent: true)
      if headers["Referer"]
        page.referrer = headers["Referer"]
        headers.delete("Referer") unless permanent
      end

      @headers.merge!(headers)
      user_agent = @headers["User-Agent"]
      accept_language = @headers["Accept-Language"]

      set_overrides(user_agent: user_agent, accept_language: accept_language)
      page.command("Network.setExtraHTTPHeaders", headers: @headers)
    end

    def add_header(header, permanent: true)
      add_headers(header, permanent: permanent)
    end

    def set_overrides(user_agent: nil, accept_language: nil, platform: nil)
      options = Hash.new
      options[:userAgent] = user_agent if user_agent
      options[:acceptLanguage] = accept_language if accept_language
      options[:platform] if platform

      page.command("Network.setUserAgentOverride", **options) if !options.empty?
    end

    def cookies
      cookies = page.command("Network.getAllCookies")["cookies"]
      cookies.map { |c| [c["name"], Cookie.new(c)] }.to_h
    end

    def set_cookie(cookie)
      page.command("Network.setCookie", **cookie)
    end

    def remove_cookie(options)
      page.command("Network.deleteCookies", **options)
    end

    def clear_cookies
      page.command("Network.clearBrowserCookies")
    end

    def url_whitelist=(wildcards)
      @url_whitelist = prepare_wildcards(wildcards)
      page.intercept_request("*") if @client && !@url_whitelist.empty?
    end

    def url_blacklist=(wildcards)
      @url_blacklist = prepare_wildcards(wildcards)
      page.intercept_request("*") if @client && !@url_blacklist.empty?
    end

    def clear_memory_cache
      page.command("Network.clearBrowserCache")
    end

    def reset
      @headers = {}
      @zoom_factor = nil
      @window_size = @original_window_size
      targets.reset
    end

    def restart
      quit
      start
    end

    def quit
      @client.close
      @process.stop
      @client = @process = @targets = nil
    end

    def crash
      command("Browser.crash")
    end

    def browser_error
      page.evaluate("_cuprite.browserError()")
    end

    def resize(**options)
      @window_size = [options[:width], options[:height]]
      page.resize(**options)
    end

    def command(*args)
      id = @client.command(*args)
      @client.wait(id: id)
    rescue DeadBrowser
      restart
      raise
    end

    def targets
      @targets ||= Targets.new(self)
    end

    private

    def start
      @headers = {}
      @process = Process.start(@options)
      @client = Client.new(self, @process.ws_url, false)
    end

    def render_options(format, opts)
      options = {}

      format ||= File.extname(opts[:path]).delete(".") || "png"
      format = "jpeg" if format == "jpg"
      raise "Not supported format: #{format}. jpeg | png | pdf" if format !~ /jpeg|png|pdf/i
      options.merge!(format: format)

      options.merge!(quality: opts[:quality] ? opts[:quality] : 75) if format == "jpeg"

      warn "Ignoring :selector in #render since full: true was given at #{caller(1..1).first}" if !!opts[:full] && opts[:selector]

      if !!opts[:full]
        width, height = page.evaluate("[document.documentElement.offsetWidth, document.documentElement.offsetHeight]")
        options.merge!(clip: { x: 0, y: 0, width: width, height: height, scale: @zoom_factor || 1.0 }) if width > 0 && height > 0
      elsif opts[:selector]
        rect = page.evaluate("document.querySelector('#{opts[:selector]}').getBoundingClientRect()")
        options.merge!(clip: { x: rect["x"], y: rect["y"], width: rect["width"], height: rect["height"], scale: @zoom_factor || 1.0 })
      end

      if @zoom_factor
        if !options[:clip]
          width, height = page.evaluate("[document.documentElement.clientWidth, document.documentElement.clientHeight]")
          options[:clip] = { x: 0, y: 0, width: width, height: height }
        end

        options[:clip].merge!(scale: @zoom_factor)
      end

      options
    end

    def find_all(method, selector, within = nil)
      begin
        elements = if within
          evaluate("_cuprite.find(arguments[0], arguments[1], arguments[2])", method, selector, within)
        else
          evaluate("_cuprite.find(arguments[0], arguments[1])", method, selector)
        end

        elements.map do |element|
          # nodeType: 3, nodeName: "#text" e.g.
          target_id, node = element.values_at("target_id", "node")
          next if node["nodeType"] != 1
          within ? node : [target_id, node]
        end.compact
      rescue JavaScriptError => e
        if e.class_name == "InvalidSelector"
          raise InvalidSelector.new(e.response, method, selector)
        end
        raise
      end
    end

    def prepare_wildcards(wc)
      Array(wc).map do |wildcard|
        if wildcard.is_a?(Regexp)
          wildcard
        else
          wildcard = wildcard.gsub("*", ".*")
          Regexp.new(wildcard, Regexp::IGNORECASE)
        end
      end
    end
  end
end
