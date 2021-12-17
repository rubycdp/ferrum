# frozen_string_literal: true

require "sinatra/base"

module Ferrum
  class Application < Sinatra::Base
    configure { set :protection, except: :frame_options }
    FERRUM_VIEWS  = "#{File.dirname(__FILE__)}/views"
    FERRUM_PUBLIC = "#{File.dirname(__FILE__)}/public"

    class TestAppError < Exception; end # rubocop:disable Lint/InheritException

    class TestAppOtherError < Exception # rubocop:disable Lint/InheritException
      def initialize(something, message)
        super(something)
        @something = something
        @message = message
      end
    end

    set :root, File.dirname(__FILE__)
    set :static, true
    set :raise_errors, true
    set :show_exceptions, false

    get "/" do
      response.set_cookie("cookie", value: "root cookie", domain: request.host, path: request.path)
      %(Hello world! <a href="with_html">Relative</a>)
    end

    get "/csp" do
      headers["Content-Security-Policy"] = %(default-src "self")
      "csp content"
    end

    get "/foo" do
      "Another World"
    end

    get "/redirect" do
      redirect "/redirect_again"
    end

    get "/redirect_again" do
      redirect "/landed"
    end

    post "/redirect_307" do
      redirect "/landed", 307
    end

    post "/redirect_308" do
      redirect "/landed", 308
    end

    get "/referer_base" do
      <<~HERE.gsub(/\n/, "")
        <a href="/get_referer">direct link</a>
        <a href="/redirect_to_get_referer">link via redirect</a>
        <form action="/get_referer" method="get"><input type="submit"></form>
      HERE
    end

    get "/redirect_to_get_referer" do
      redirect "/get_referer"
    end

    get "/get_referer" do
      request.referer.nil? ? "No referer" : "Got referer: #{request.referer}"
    end

    get "/host" do
      "Current host is #{request.scheme}://#{request.host}:#{request.port}"
    end

    get "/redirect/:times/times" do
      times = params[:times].to_i
      if times.zero?
        "redirection complete"
      else
        redirect "/redirect/#{times - 1}/times"
      end
    end

    get "/landed" do
      "You landed"
    end

    post "/landed" do
      "You post landed: #{params.dig(:form, 'data')}"
    end

    get "/with-quotes" do
      %q("No," he said, "you can't do that.")
    end

    get "/form/get" do
      %(<pre id="results">#{params[:form].to_yaml}</pre>)
    end

    post "/relative" do
      %(<pre id="results">#{params[:form].to_yaml}</pre>)
    end

    get "/favicon.ico" do
      nil
    end

    post "/redirect" do
      redirect "/redirect_again"
    end

    delete "/delete" do
      "The requested object was deleted"
    end

    get "/delete" do
      "Not deleted"
    end

    get "/redirect_back" do
      redirect back
    end

    get "/redirect_secure" do
      redirect "https://#{request.host}:#{request.port}/host"
    end

    get "/slow_response" do
      sleep 2
      "Finally!"
    end

    get "/set_cookie" do
      set_stealth_cookie
    end

    get "/set_cookie_slow" do
      sleep 1
      set_stealth_cookie
    end

    get "/get_cookie" do
      request.cookies["stealth"]
    end

    get "/get_header" do
      env["HTTP_FOO"]
    end

    get "/get_header_via_redirect" do
      redirect "/get_header"
    end

    get "/error" do
      raise TestAppError, "some error"
    end

    get "/other_error" do
      raise TestAppOtherError.new("something", "other error")
    end

    get "/load_error" do
      raise LoadError
    end

    get "/with.*html" do
      erb :with_html, locals: { referrer: request.referrer }
    end

    get "/with_title" do
      <<-HTML
        <title>#{params[:title] || 'Test Title'}</title>
        <body>
          <svg><title>abcdefg</title></svg>
        </body>
      HTML
    end

    get "/download.csv" do
      content_type "text/csv"
      "This, is, comma, separated"
    end

    get "/:view" do |view|
      erb view.to_sym, locals: { referrer: request.referrer }
    end

    post "/form" do
      self.class.form_post_count += 1
      %(<pre id="results">#{params[:form].merge('post_count' => self.class.form_post_count).to_yaml}</pre>)
    end

    post "/upload_empty" do
      if params[:form][:file].nil?
        "Successfully ignored empty file field."
      else
        "Something went wrong."
      end
    end

    post "/upload" do
      buffer = []
      buffer << "Content-type: #{params.dig(:form, :document, :type)}"
      buffer << "File content: #{params.dig(:form, :document, :tempfile).read}"
      buffer.join(" | ")
    rescue StandardError
      "No file uploaded"
    end

    post "/upload_multiple" do
      docs = params.dig(:form, :multiple_documents)
      buffer = [docs.size.to_s]
      docs.each do |doc|
        buffer << "Content-type: #{doc[:type]}"
        buffer << "File content: #{doc[:tempfile].read}"
      end
      buffer.join(" | ")
    rescue StandardError
      "No files uploaded"
    end

    get "/apple-touch-icon-precomposed.png" do
      halt(404)
    end

    class << self
      attr_accessor :form_post_count
    end

    @form_post_count = 0

    helpers do
      def requires_credentials(login, password)
        return if authorized?(login, password)

        headers["WWW-Authenticate"] = %(Basic realm="Restricted Area")
        halt 401, "Not authorized\n"
      end

      def authorized?(login, password)
        @auth ||= Rack::Auth::Basic::Request.new(request.env)
        @auth.provided? && @auth.basic? && @auth.credentials && (@auth.credentials == [login, password])
      end
    end

    get "/ferrum/test.js" do
      content_type :js
      File.read("#{FERRUM_PUBLIC}/test.js")
    end

    get "/ferrum/add_style_tag.css" do
      content_type :css
      File.read("#{FERRUM_PUBLIC}/add_style_tag.css")
    end

    get "/ferrum/jquery.min.js" do
      content_type :js
      File.read("#{FERRUM_PUBLIC}/jquery-1.11.3.min.js")
    end

    get "/ferrum/jquery-ui.min.js" do
      content_type :js
      File.read("#{FERRUM_PUBLIC}/jquery-ui-1.11.4.min.js")
    end

    get "/ferrum/unexist.png" do
      halt 404
    end

    get "/ferrum/status/:status" do
      status params["status"]
      render_view "with_different_resources"
    end

    get "/ferrum/redirect_to_headers" do
      redirect "/ferrum/headers"
    end

    get "/ferrum/redirect" do
      redirect "/ferrum/with_different_resources"
    end

    get "/ferrum/get_cookie" do
      request.cookies["stealth"]
    end

    get "/ferrum/slow" do
      sleep 0.2
      "slow page"
    end

    get "/ferrum/really_slow" do
      sleep 3
      "really slow page"
    end

    get "/ferrum/basic_auth" do
      requires_credentials("login", "pass")
      render_view :basic_auth
    end

    post "/ferrum/post_basic_auth" do
      requires_credentials("login", "pass")
      "Authorized POST request"
    end

    get "/ferrum/cacheable" do
      cache_control :public, max_age: 60
      etag "deadbeef"
      "Cacheable request <a href='/ferrum/cacheable'>click me</a>"
    end

    get "/ferrum/:view" do |view|
      render_view view
    end

    get "/ferrum/arbitrary_path/:status/:remaining_path" do
      status params["status"].to_i
      params["remaining_path"]
    end

    protected

    def render_view(view)
      erb File.read("#{FERRUM_VIEWS}/#{view}.erb")
    end

    def set_stealth_cookie
      cookie_value = "test_cookie"
      response.set_cookie("stealth", cookie_value)
      "Cookie set to #{cookie_value}"
    end
  end
end
