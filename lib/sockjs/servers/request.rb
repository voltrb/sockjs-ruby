# encoding: utf-8

require "uri"

module SockJS
  #This is the SockJS wrapper for a Rack env hash-like.  Currently it requires
  #that we're running under Thin - someday we may break this out such that can
  #adapt to other webservers or compatiblity layers.  For now: do your SockJS
  #stuff in Thin.
  #
  class Request
    attr_reader :env
    def initialize(env)
      @env = env
    end

    # request.path_info
    # => /echo/abc
    def path_info
      env["PATH_INFO"]
    end

    # request.http_method
    # => "GET"
    def http_method
      env["REQUEST_METHOD"]
    end

    def async_callback
      env["async.callback"]
    end

    def async_close
      env["async.close"]
    end

    def on_close(&block)
      async_close.callback( &block)
      async_close.errback(  &block)
    end

    # request.headers["origin"]
    # => http://foo.bar
    def headers
      @headers ||=
        begin
          permitted_keys = /^(CONTENT_(LENGTH|TYPE))$/

            @env.reduce(Hash.new) do |headers, (key, value)|
            if key.match(/^HTTP_(.+)$/) || key.match(permitted_keys)
              headers[$1.downcase.tr("_", "-")] = value
            end

          headers
            end
        end
    end


    # request.query_string["callback"]
    # => "myFn"
    def query_string
      @query_string ||=
        begin
          @env["QUERY_STRING"].split("=").each_slice(2).each_with_object({}) do |pair, buffer|
            buffer[pair.first] = pair.last
          end
        end
    end


    # request.cookies["JSESSIONID"]
    # => "123sd"
    def cookies
      @cookies ||=
        begin
          ::Rack::Request.new(@env).cookies
        end
    end


    # request.data.read
    # => "message"
    def data
      @env["rack.input"]
    end
    HTTP_1_0     ||= "HTTP/1.0"
    HTTP_VERSION ||= "version"


    def http_1_0?
      self.headers[HTTP_VERSION] == HTTP_1_0
    end

    def origin
      self.headers["origin"] || "*"
    end

    def content_type
      self.headers["content-type"]
    end

    def callback
      callback = self.query_string["callback"] || self.query_string["c"]
      URI.unescape(callback) if callback
    end

    def session_id
      self.cookies["JSESSIONID"] || "dummy"
    end

    def fresh?(etag)
      self.headers["if-none-match"] == etag
    end
  end
end
