# frozen_string_literal: true

require "sinatra/base"

module Ferrum
  class Application < Sinatra::Base
    configure { set :protection, except: :frame_options }
    FERRUM_VIEWS  = "#{File.dirname(__FILE__)}/views"
    FERRUM_PUBLIC = "#{File.dirname(__FILE__)}/public"

    set :root, File.dirname(__FILE__)
    set :static, true
    set :raise_errors, true
    set :show_exceptions, false

    helpers do
      def requires_credentials(login, password)
        return if authorized?(login, password)

        headers["WWW-Authenticate"] = %(Basic realm="Restricted Area")
        halt(401, "Not authorized\n")
      end

      def authorized?(login, password)
        @auth ||= Rack::Auth::Basic::Request.new(request.env)
        @auth.provided? && @auth.basic? && @auth.credentials && (@auth.credentials == [login, password])
      end
    end

    get "/test.js" do
      content_type :js
      File.read("#{FERRUM_PUBLIC}/test.js")
    end

    get "/jquery.min.js" do
      content_type :js
      File.read("#{FERRUM_PUBLIC}/jquery-3.7.1.min.js")
    end

    get "/jquery-ui.min.js" do
      content_type :js
      File.read("#{FERRUM_PUBLIC}/jquery-ui-1.13.2.min.js")
    end

    get "/add_style_tag.css" do
      content_type :css
      File.read("#{FERRUM_PUBLIC}/add_style_tag.css")
    end

    get "/" do
      response.set_cookie("cookie", value: "root cookie", domain: request.host, path: request.path)
      %(Hello world! <a href="with_html">Relative</a>)
    end

    get "/set_cookie" do
      set_stealth_cookie
    end

    get "/get_cookie" do
      request.cookies["stealth"]
    end

    get "/custom/get_cookie" do
      request.cookies["stealth"]
    end

    get "/attachment.pdf" do
      attachment("attachment.pdf")
      send_file("attachment.pdf")
    end

    get "/foo" do
      "Another World"
    end

    get "/landed" do
      "You landed"
    end

    post "/landed" do
      "You post landed: #{params.dig(:form, 'data')}"
    end

    get "/host" do
      "Current host is #{request.scheme}://#{request.host}:#{request.port}"
    end

    get "/unicode" do
      File.read("#{FERRUM_VIEWS}/unicode.html")
    end

    get "/csp" do
      headers["Content-Security-Policy"] = %(default-src "self")
      "csp content"
    end

    get "/show_cookies/set_cookie_slow" do
      sleep 1
      set_stealth_cookie
    end

    get "/redirect" do
      redirect "/redirect_again"
    end

    get "/redirect_again" do
      redirect "/landed"
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

    get "/apple-touch-icon-precomposed.png" do
      halt(404)
    end

    get "/unexist.png" do
      halt(404)
    end

    get "/server_error" do
      halt(500)
    end

    get "/status/:status" do
      status params["status"]
      render_view "with_different_resources"
    end

    get "/redirect_to_headers" do
      redirect "/headers"
    end

    get "/slow" do
      sleep 0.2
      "slow page"
    end

    get "/really_slow" do
      sleep 3
      "really slow page"
    end

    get "/basic_auth" do
      requires_credentials("login", "pass")
      render_view :basic_auth
    end

    post "/post_basic_auth" do
      requires_credentials("login", "pass")
      "Authorized POST request"
    end

    get "/cacheable" do
      cache_control :public, max_age: 60
      etag "deadbeef"
      %(<link rel="icon" href="data:,">Cacheable request <a href='/cacheable'>click me</a>)
    end

    get "/arbitrary_path/:status/:remaining_path" do
      status params["status"].to_i
      params["remaining_path"]
    end

    post "/ping" do
      # Sleeping to simulate a server that does not send a response to PING requests
      sleep 5
      halt(204)
    end

    get "/:view" do |view|
      render_view view
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
