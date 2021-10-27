# frozen_string_literal: true

require "tempfile"
require "webrick"
require "webrick/httpproxy"

module Ferrum
  class Proxy
    def self.start(**args)
      new(**args).tap(&:start)
    end

    attr_reader :host, :port, :user, :password

    def initialize(host: "127.0.0.1", port: 0, user: nil, password: nil)
      @file = nil
      @host = host
      @port = port
      @user = user
      @password = password
      at_exit { stop }
    end

    def start
      options = {
        ProxyURI: nil, ServerType: Thread,
        Logger: Logger.new(IO::NULL), AccessLog: [],
        BindAddress: host, Port: port
      }

      if user && password
        @file = Tempfile.new("htpasswd")
        htpasswd = WEBrick::HTTPAuth::Htpasswd.new(@file.path)
        htpasswd.set_passwd "Proxy Realm", user, password
        htpasswd.flush
        authenticator = WEBrick::HTTPAuth::ProxyBasicAuth.new(Realm: "Proxy Realm",
                                                              UserDB: htpasswd,
                                                              Logger: Logger.new(IO::NULL))
        options.merge!(ProxyAuthProc: authenticator.method(:authenticate).to_proc)
      end

      @server = WEBrick::HTTPProxyServer.new(**options)
      @server.start
      @port = @server.config[:Port]
    end

    def rotate(host:, port:, user: nil, password: nil)
      credentials = "#{user}:#{password}@" if user && password
      proxy_uri = "schema://#{credentials}#{host}:#{port}"
      @server.config[:ProxyURI] = URI.parse(proxy_uri)
    end

    def stop
      @file&.unlink
      @server.shutdown
    end
  end
end
