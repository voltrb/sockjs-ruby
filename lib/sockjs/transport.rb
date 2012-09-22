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

  class MethodNotSupported < StandardError
    attr_reader :request_method, :allowed_methods, :path
    def initialize(env, allowed_methods)
      @request_method = env["REQUEST_METHOD"]
      @path = env["SCRIPT_NAME"] + env["PATH_INFO"]
      @allowed_methods = allowed_methods
      super("Method not supported: #@request_method for #@path (allowed: #{@allowed_methods.join(", ")})")
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
      rescue
        raise MethodNotSupported.new(env, @method_map.keys)
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
      def transports
        @transports ||= Hash.new{|h,k| h[k] = []}
      end

      def register(prefix, method)
        Transport.transports[prefix] << [method, self]
      end

      def prefix_map
        Hash[transports.map{|prefix, transports|
          [prefix, MethodMap.new(Hash[transports])]
        }]
      end
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
      handle(request)
    end

    def response(request, status, options = Hash.new, &block)
      response = self.response_class.new(request, status)

      case block && block.arity
      when nil # no block
        SockJS.debug "There's no block for response(request, #{status}, #{options.inspect}), closing the response."
        response.finish
      when 1
        SockJS.debug "Calling block in response(request, #{status}, #{options.inspect}) with response."
        block.call(response)
      when 2
        begin
          if session = self.get_session(session_key(request))
            session.buffer = Buffer.new(:open)
          elsif session.nil? && options[:session] == :create
            session = self.create_session(session_key(request))
            session.buffer = Buffer.new
          end

          if session
            response.session = session

            if options[:data]
              session.with_response_and_transport(response, self) do
                session.receive_message(request, options[:data])

                SockJS.debug "Calling block in response(request, #{status}, #{options.inspect}) with response and session."
                block.call(response, session)
              end
            else
              session.with_response_and_transport(response, self) do
                SockJS.debug "Calling block in response(request, #{status}, #{options.inspect}) with response and session."
                block.call(response, session)
              end
            end
          else
            SockJS.debug "Session can't be retrieved."

            SockJS.debug "Calling block in response(request, #{status}, #{options.inspect}) with response and nil instead of session."
            block.call(response, nil)
          end
        rescue SockJS::SessionUnavailableError => error
          self.handle_session_unavailable(error, response)
        end
      else
        raise ArgumentError.new("Block in response takes either 1 or 2 arguments!")
      end

      response
    end

    def handle(request)
      handle_request(request)
    rescue HttpError => error
      error.to_response(self, request)
    end

    def handle_session_unavailable(error, response)
      session = error.session

      # We don't need to reset the buffer, it's convenient to keep it
      # as we're serving the last frame, but we do need a new response.

      session.with_response_and_transport(response, self) do
        # We have to run the handler, so we set the headers
        # and send the prelude if there's any. However we must
        # not run the user app, otherwise baaad stuff can happen.
        # error.session.run_user_app(response)
        session.finish
      end

      # TODO: What shall we do about it? We need to call session.close
      # so we can send the closing frame with a DIFFERENT message.

      # Noooo, we don't need to call session.close, do we? We just need to send the bloody closing frame, huh?

      # Aaaaactually we DO, because we have to reset the bloody @close_timer!

      # This helps with identifying open connections.
    end

    def session_key(request)
      request.env['sockjs.session-key']
    end

    # There's a session:
    #   a) It's closing -> Send c[3000,"Go away!"] AND END
    #   b) It's open:
    #      i) There IS NOT any consumer -> OK. AND CONTINUE
    #      i) There IS a consumer -> Send c[2010,"Another con still open"] AND END
    def get_session(session_key)
      # The block is supposed to return session.
      session = connection.sessions[session_key]

      if session
        if session.closing?
          # response.body is closed, why?
          SockJS.debug "get_session: session is closing"
          raise SessionUnavailableError.new(session)
        elsif session.open? || session.newly_created? || session.opening?
          SockJS.debug "get_session: session retrieved successfully"
          return session
        # TODO: Should be alright now, check 6aeeaf1fd69c
         elsif session.response # THIS is an utter piece of sssshhh ... of course there's a response once we open it!
           SockJS.debug "get_session: another connection still open"
           raise SessionUnavailableError.new(session, 2010, "Another connection still open")
        else
          raise "We should never get here!\nsession.status: #{session.status}, has session response: #{!! session.response}"
        end
      else
        SockJS.debug "get_session: session for #{session_key.inspect} doesn't exist."
        return nil
      end
    end

    def create_session(session_key, response = nil, preamble = nil)
      response.write(preamble) if preamble

      return self.connection.create_session(session_key, self)
    end
  end
end
