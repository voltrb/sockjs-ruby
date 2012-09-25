# encoding: utf-8

require "sockjs/buffer"
require "sockjs/session"
require "sockjs/servers/thin"

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
        self.prefix
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

    def session_class
      SockJS::SessionWitchCachedMessages
    end

    # TODO: Make it use the adapter user uses.
    def response_class
      SockJS::Thin::Response
    end

    # Used for pings.
    def empty_string
      "\n"
    end

    def format_frame(payload)
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

    def build_response(request, status)
      response_class.new(request, status)
    end

    def empty_response(request, status)
      response = build_response(request, status)
      SockJS.debug "There's no block for response(request, #{status}, #{options.inspect}), closing the response."
      response.finish
      return response
    end

    def response(request, status, options = nil)
      options ||= {}
      unless block_given?
        empty_response(request, status)
      else
        response = build_response(request, status)
        yield(response)
        response
      end
    end

    alias sessionless_response response

    def handle(request)
      handle_request(request)
    rescue HttpError => error
      error.to_response(self, request)
    end
  end

  class SessionTransport < Transport
    def self.routing_prefix
      %r{^/(?<server-key>[^/]+)/(?<session-key>)#{self.prefix}$}
    end

    # There's a session:
    #   a) It's closing -> Send c[3000,"Go away!"] AND END
    #   b) It's open:
    #      i) There IS NOT any consumer -> OK. AND CONTINUE
    #      i) There IS a consumer -> Send c[2010,"Another con still open"] AND END
    def get_session(session_key)
      session = connection.get_session(session_key)
    end

    def create_session(session_key, response = nil, preamble = nil)
      response.write(preamble) if preamble

      return self.connection.create_session(session_key, self)
    end

    def handle_session_unavailable(error, response)
      session = error.session

      session.with_response_and_transport(response, self) do
        session.finish
      end
    end

    def server_key(request)
      (request.env['rack.routing_args'] || {})['server-key']
    end

    def session_key(request)
      (request.env['rack.routing_args'] || {})['session-key']
    end

    def response(request, status, options = nil)
      options ||= {}

      unless block_given?
        empty_response(request, status)
      else
        begin
          if session = get_session(session_key(request))
            session.buffer = Buffer.new(:open)
          elsif options[:session] == :create
            session = create_session(session_key(request))
            session.buffer = Buffer.new
          end

          response = build_response(request, status)

          if session
            response.session = session

            session.with_response_and_transport(response, self) do
              if options[:data]
                session.receive_message(request, options[:data])
              end

              SockJS.debug "Calling block in response(request, #{status}, #{options.inspect}) with response and session."
              yield(response, session)
            end
          else
            SockJS.debug "Session can't be retrieved."

            SockJS.debug "Calling block in response(request, #{status}, #{options.inspect}) with response and nil instead of session."
            yield(response, nil)
          end
          return response
        rescue SockJS::SessionUnavailableError => error
          self.handle_session_unavailable(error, response)
        end
      end
    end
  end
end
