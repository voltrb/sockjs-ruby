# encoding: utf-8

require "sockjs"
require "sockjs/transport"
require "sockjs/servers/thin"

# Transports.
require "sockjs/transports/info"
require "sockjs/transports/eventsource"
require "sockjs/transports/htmlfile"
require "sockjs/transports/iframe"
require "sockjs/transports/jsonp"
require "sockjs/transports/raw_websocket"
require "sockjs/transports/websocket"
require "sockjs/transports/welcome_screen"
require "sockjs/transports/xhr"

# This is a Rack middleware for SockJS.
#
# @example
#  require "rack/sockjs"
#
#  use SockJS, "/echo" do |connection|
#    connection.subscribe do |session, message|
#      session.send(message)
#    end
#  end
#
#  use SockJS, "/disabled_websocket_echo",
#    websocket: false do |connection|
#    # ...
#  end
#
#  use SockJS, "/close" do |connection|
#    connection.session_open do |session|
#      session.close(3000, "Go away!")
#    end
#  end
#
#  run MyApp
#
#
#@example
#
#  require 'rack/sockjs'
#
#  map "/echo", Rack::SockJS.build do |connection|
#    connection.subscribe do |session, message|
#      session.send(message)
#    end
#  end
#
#  run MyApp
#
#
# #or
#
#  run Rack::SockJS.build do |connection|
#    connection.session_open do |session|
#      session.close(3000, "Go away!")
#    end
#  end

module Rack
  class SockJS
    SERVER_SESSION_REGEXP = %r{/([^/]*)/([^/]*)}
    DEFAULT_OPTIONS = {
      :sockjs_url => "http://cdn.sockjs.org/sockjs-#{SockJS::PROTOCOL_VERSION}.min.js"
    }

    class ResetScriptName
      def initialize(app)
        @app = app
      end

      def call(env)
        env["PREVIOUS_SCRIPT_NAME"], env["SCRIPT_NAME"] = env["SCRIPT_NAME"], ''
        result = @app.call(env)
      ensure
        env["SCRIPT_NAME"] = env["PREVIOUS_SCRIPT_NAME"]
      end
    end

    class ExtractServerAndSession
      def initialize(app)
        @app = app
      end

      def call(env)
        match = SERVER_SESSION_REGEXP.match(env["SCRIPT_NAME"])
        env["sockjs.server-id"] = match[1]
        env["sockjs.session-key"] = match[2]
        return @app.call(env)
      end
    end

    def self.build(options = nil, &block)
      #TODO refactor Connection to App
      connection = ::SockJS::Connection.new(&block)

      options ||= {}

      options = DEFAULT_OPTIONS.merge(options)
      transports = SockJS::Transports.prefix_map

      Rack::Builder.new do
        use Rack::SockJS::ResetScriptName

        map %r{/iframe.*[.]html?} do
          run SockJS::Transports::IFrame.new(connection, options)
        end

        map '/info' do
          run SockJS::Transports::Info.new(connection, options)
        end

        map '/websocket' do
          run SockJS::Transports::RawWebsocket.new(connection, options)
        end

        map SERVER_SESSION_REGEXP do
          transports.each_pair(path, app) do
            map path do
              use ExtractServerAndSession
              run app.new(connection, options)
            end
          end
        end

        run SockJS::Transports::WelcomeScreen.new(options)
      end
    end

    def initialize(app, prefix = "/echo", options = Hash.new, &block)
      @app, @prefix, @options = app, prefix, options

      unless block
        raise "You have to provide SockJS app as a block argument!"
      end

      # Validate options.
      if options[:sockjs_url].nil?
        raise RuntimeError.new("You have to provide sockjs_url in options, it's required for the iframe transport!")
      end

      @connection ||= begin
        ::SockJS::Connection.new(&block)
      end
    end

    def call(env)
      request = ::SockJS::Thin::Request.new(env)
      matched = request.path_info.match(/^#{Regexp.quote(@prefix)}/)

      matched ? debug_process_request(request) : @app.call(env)
    end

    def debug_process_request(request)
      headers = request.headers.select { |key, value| not %w{version host accept-encoding}.include?(key.to_s) }
      ::SockJS.puts "\n~ \e[31m#{request.http_method} \e[32m#{request.path_info.inspect}#{" " + headers.inspect unless headers.empty?} \e[0m(\e[34m#{@prefix} app\e[0m)"
      headers = headers.map { |key, value| "-H '#{key}: #{value}'" }.join(" ")
      ::SockJS.puts "\e[90mcurl -X #{request.http_method} http://localhost:8081#{request.path_info} #{headers}\e[0m"

      self.process_request(request).tap do |response|
        ::SockJS.debug response.inspect
      end
    end

    def process_request(request)
      prefix     = request.path_info.sub(/^#{Regexp.quote(@prefix)}\/?/, "")
      method     = request.http_method
      transports = ::SockJS::Transport.handlers(prefix)
      transport  = transports.find { |handler| handler.method == method }
      if transport
        ::SockJS.debug "Transport: #{transport.inspect}"
        EM.next_tick do
          handler = transport.new(@connection, @options)
          handler.handle(request)
        end
        ::SockJS::Thin::DUMMY_RESPONSE
      elsif transport.nil? && ! transports.empty?
        # Unsupported method.
        ::SockJS.debug "Method not supported!"
        methods = transports.map { |transport| transport.method }
        [405, {"Allow" => methods.join(", ") }, []]
      else
        body = <<-HTML
          <!DOCTYPE html>
          <html>
            <body>
              <h1>Handler Not Found</h1>
              <ul>
                <li>Prefix: #{prefix.inspect}</li>
                <li>Method: #{method.inspect}</li>
                <li>Handlers: #{::SockJS::Transport.subclasses.inspect}</li>
              </ul>
            </body>
          </html>
        HTML
        ::SockJS.debug "Handler not found!"
        [404, {"Content-Type" => "text/html; charset=UTF-8", "Content-Length" => body.bytesize.to_s}, [body]]
      end
    end
  end
end
