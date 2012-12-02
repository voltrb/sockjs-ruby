# encoding: utf-8

require "sockjs/transport"

module SockJS
  module Transports
    class XHRPost < SessionTransport
      register 'POST', 'xhr'

      include Transactional

      def session_opened(session)
        session.close_response
      end

      def session_continues(session)
        session.process_buffer
        session.close_response
      end

      def opening_response(session, request)
        response = response_class.new(request, 200)

        response.set_content_type(:javascript)
        response.set_access_control(request.origin)
        response.set_session_id(request.session_id)
        response
      end

      def continuing_response(session, request)
        response = response_class.new(request, 200)
        response.set_content_type(:plain)
        response
      end
    end

    class XHROptions < Transport
      register 'OPTIONS', 'xhr'

      def setup_response(request, response)
        response.set_allow_options_post
        response.set_cache_control
        response.set_access_control(request.origin)
        response.set_session_id(request.session_id)
      end

      def handle_request(request)
        response = build_response(request, 204)
        response.finish
        return response
      end
    end

    class XHRSendPost < SessionTransport
      register 'POST', 'xhr_send'
      cant_open

      def session_continues(session)
        session.close_response
      end

      def continuing_response(session, request)
        response = response_class.new(request, 204)

        response.set_content_type(:plain)
        response.set_access_control(request.origin)
        response.set_session_id(request.session_id)
        response.write_head

        response
      end

      #XXX Maybe this needs to close the session - here or in SessionTransport
      def opening_response(session, request)
        raise SockJS::HttpError.new(404, "Session is not open!") { |response|
          response.set_session_id(request.session_id)
        }
      end
    end

    class XHRSendOptions < XHROptions
      register 'OPTIONS', 'xhr_send'
    end

    class XHRStreamingPost < SessionTransport
      PREAMBLE ||= "h" * 2048 + "\n"

      register 'POST', 'xhr_streaming'

      def session_opening(session)
        session.wait
      end

      def opening_response(session, request)
        response = build_response(request, 200)
        request.on_close{ session.on_close }
        return response
      end

      def setup_response(request, response)
        response.set_content_type(:javascript)
        response.set_access_control(request.origin)
        response.set_session_id(request.session_id)
        response.write_head
        response.write(PREAMBLE)
      end

      def handle_session_unavailable(error, response)
        response.write(PREAMBLE)
        super(error, response)
      end
    end

    class XHRStreamingOptions < XHROptions
      register 'OPTIONS', 'xhr_streaming'
    end
  end
end
