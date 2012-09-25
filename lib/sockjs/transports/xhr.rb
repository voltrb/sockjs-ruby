# encoding: utf-8

require "sockjs/transport"

module SockJS
  module Transports
    class XHRPost < SessionTransport
      register 'POST', '/xhr'

      def handle(request)
        response(request, 200, session: :create) do |response, session|
          unless session.newly_created?
            response.set_content_type(:plain)
            session.process_buffer
          else
            response.set_content_type(:javascript)
            response.set_access_control(request.origin)
            response.set_session_id(request.session_id)

            session.open!
          end
        end
      end
    end

    class XHROptions < SessionTransport
      register 'OPTIONS', '/xhr'

      def handle(request)
        sessionless_response(request, 204) do |response|
          response.set_allow_options_post
          response.set_cache_control
          response.set_access_control(request.origin)
          response.set_session_id(request.session_id)
          response.finish
        end
      end
    end

    class XHRSendPost < SessionTransport
      register 'POST', '/xhr_send'

      def handle(request)
        response(request, 204, data: request.data.read) do |response, session|
          if session
            response.set_content_type(:plain)
            response.set_access_control(request.origin)
            response.set_session_id(request.session_id)
            response.write_head
          else
            raise SockJS::HttpError.new(404, "Session is not open!") { |response|
              response.set_session_id(request.session_id)
            }
          end
        end

      rescue SockJS::HttpError => error
        error.to_response(self, request)
      end
    end

    class XHRSendOptions < XHROptions
      register 'OPTIONS', '/xhr_send'
    end

    class XHRStreamingPost < SessionTransport
      PREAMBLE ||= "h" * 2048 + "\n"

      register 'POST', '/xhr_streaming'

      def session_class
        SockJS::Session
      end

      def handle(request)
        response(request, 200, session: :create) do |response, session|
          response.set_content_type(:javascript)
          response.set_access_control(request.origin)
          response.set_session_id(request.session_id)
          response.write_head

          # IE requires 2KB prefix:
          # http://blogs.msdn.com/b/ieinternals/archive/2010/04/06/comet-streaming-in-internet-explorer-with-xmlhttprequest-and-xdomainrequest.aspx
          response.write(PREAMBLE)

          if session.newly_created?
            session.open!
          end

          session.wait(response)
        end
      end

      def handle_session_unavailable(error, response)
        response.write(PREAMBLE)
        super(error, response)
      end
    end

    class XHRStreamingOptions < XHROptions
      register 'OPTIONS', '/xhr_streaming'
    end
  end
end
