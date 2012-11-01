# encoding: utf-8

require "sockjs/transport"

module SockJS
  module Transports
    class EventSource < SessionTransport
      register 'GET', 'eventsource'

      def session_opening(session)
        session.wait
      end

      def opening_response(session, request)
        response = response_class.new(request, 200)
        response.set_content_type(:event_stream)
        response.set_session_id(request.session_id)
        response.set_no_cache
        response.write_head

        # Opera needs to hear two more initial new lines.
        response.write("\r\n")
        response
      end

      def format_frame(session, payload)
        raise TypeError.new("Payload must not be nil!") if payload.nil?

        ["data: ", payload, "\r\n\r\n"].join
      end
    end
  end
end
