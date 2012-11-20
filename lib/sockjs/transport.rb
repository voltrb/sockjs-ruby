# encoding: utf-8

require "sockjs/session"
require "sockjs/servers/thin"

require 'rack/mount'

module SockJS
  class SessionUnavailableError < StandardError
    attr_reader :status, :session

    def initialize(session, status = nil, message = nil)
      @session, @status, @message = session, status, message
    end
  end

  class Transport
    class MethodMap
      def initialize(map)
        @method_map = map
      end
      attr_reader :method_map

      def call(env)
        app = @method_map.fetch(env["REQUEST_METHOD"])
        app.call(env)
      rescue KeyError
        ::SockJS.debug "Method not supported!"
        [405, {"Allow" => methods_map.keys.join(", ") }, []]
      end
    end

    class MethodNotSupportedApp
      def initialize(methods)
        @allowed_methods = methods
      end

      def response
        @response ||=
          [405, {"Allow" => @allowed_methods.join(",")}, []].freeze
      end

      def call(env)
        return response
      end
    end

    #XXX Remove
    # @deprecated: See response.rb
    CONTENT_TYPES ||= {
      plain: "text/plain; charset=UTF-8",
      html: "text/html; charset=UTF-8",
      javascript: "application/javascript; charset=UTF-8",
      event_stream: "text/event-stream; charset=UTF-8"
    }

    module ClassMethods
      def add_routes(route_set, connection, options)
        method_catching = Hash.new{|h,k| h[k] = []}
        @transports.each do |transport_class|
          transport_class.add_route(route_set, connection, options)
          method_catching[transport_class.routing_prefix] << transport_class.method
        end
        method_catching.each_pair do |prefix, methods|
          route_set.add_route(MethodNotSupportedApp.new(methods), {:path_info => prefix}, {})
        end
      end

      def routing_prefix
        case prefix
        when String
          "/" + prefix
        when Regexp
          prefix
        end
      end

      def route_conditions
        {
          :request_method => self.method,
          :path_info => self.routing_prefix
        }
      end

      def add_route(route_set, connection, options)
        route_set.add_route(self.new(connection, options), route_conditions, {})
      end

      def transports
        @transports ||= []
      end

      def register(method, prefix)
        @prefix = prefix
        @method = method
        Transport.transports << self
      end
      attr_reader :prefix, :method
    end
    extend ClassMethods

    # Instance methods.
    attr_reader :connection, :options
    def initialize(connection, options)
      @connection, @options = connection, options
      options[:websocket] = true unless options.has_key?(:websocket)
      options[:cookie_needed] = true unless options.has_key?(:cookie_needed)
    end

    # TODO: Make it use the adapter user uses.
    def response_class
      SockJS::Thin::Response
    end

    # Used for pings.
    def empty_string
      "\n"
    end

    def format_frame(session, payload)
      raise TypeError.new("Payload must not be nil!") if payload.nil?

      "#{payload}\n"
    end

    def call(env)
      request = ::SockJS::Thin::Request.new(env)
      EM.next_tick do
        handle(request)
      end
      ::SockJS::Thin::DUMMY_RESPONSE
    end

    def handle(request)
      handle_request(request)
    rescue Object => error
      SockJS.debug "Error while handling request: #{([error.inspect] + error.backtrace).join("\n")}"
      error_response(error, request)
    end

    def handle_request(request)
      response = build_response(request, 200)
      response.finish
      return response
    end

    def build_response(request, status)
      response = response_class.new(request, status)
      setup_response(request, response)
      return response
    end
    alias sessionless_response build_response

    def setup_response(request, response)
    end

    def empty_response(request, status)
      response = build_response(request, status)
      SockJS.debug "There's no block for response(request, #{status}, #{options.inspect}), closing the response."
      response.finish
      return response
    end

    def error_response(error, request)
      SockJS.debug "Error raised: #{error.inspect}"
      case error
      when SockJS::HttpError
        error.to_response(self, request)
      else
        response = response_class.new(request, 500)
        response.write(error.message)
        response.finish
      end
    end
  end

  #Transaction transports exchange data with clients on a request/response
  #basis.  As a result, client application messages need to be queued for the
  #next client request.
  module Transactional
    def data_queued(session)
    end

    def session_continues(session)
      session.send_transmit_queue
    end
  end

  class SessionTransport < Transport
    def self.routing_prefix
      ::Rack::Mount::Strexp.new("/:server_key/:session_key/#{self.prefix}")
    end

    # There's a session:
    #   a) It's closing -> Send c[3000,"Go away!"] AND END
    #   b) It's open:
    #      i) There IS NOT any consumer -> OK. AND CONTINUE
    #      i) There IS a consumer -> Send c[2010,"Another con still open"] AND END
    def handle_session_unavailable(error, response)
      session = error.session
      session.response = error.response
      session.finish
    end

    def server_key(request)
      (request.env['rack.routing_args'] || {})['server-key']
    end

    def session_key(request)
      (request.env['rack.routing_args'] || {})['session-key']
    end

    def handle_request(request)
      SockJS::debug(request.inspect)

      begin
        session = connection.get_session(session_key(request))
        return session.receive_request(request, self)
      rescue SockJS::SessionUnavailableError => error
        handle_session_unavailable(error)
      end
    end

    def request_data(request)
      request.data.string
    end

    def unknown_session(request)
      response = build_response(request)
      response.set_content_type(:plain)
      response.set_session_id(request.session_id)
      return response
    end

    def opening_response(session, request)
      #default assumption is that the transport can't open sessions
      response = unknown_session(request)
      raise SockJS::SessionUnavailableError.new(session, response)
    end

    def continuing_response(session, request)
      raise NotImplementedError
    end

    def session_opened(session)
      session.close_response
    end

    def session_continues(session)
    end

    def data_queued(session)
      session.send_transmit_queue
    end
  end
end
