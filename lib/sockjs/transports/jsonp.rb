# encoding: utf-8

require "sockjs/transport"

module SockJS
  module Transports

    # This is the receiver.
    class JSONP < SessionTransport
      register 'GET', 'jsonp'

      #XXX May cause issues with single transport
      #Move callback_function to response?
      attr_accessor :callback_function

      def callback_required_response
        sessionless_response(request, 500) do |response|
          response.set_content_type(:html)
          response.write('"callback" parameter required')
        end
      end

      def opening_response(session, request)
        if request.callback
          session.data[:callback] = request.callback
          response = response_class.new(request, 200)

          response.set_content_type(:javascript)
          response.set_access_control(request.origin)
          response.set_no_cache
          response.set_session_id(request.session_id)
          return response
        else
          callback_required_response
        end
      end

      def continuing_response(session, request)
        if request.callback
          session.data[:callback] = request.callback
          response = response_class.new(request, 200)
          response.set_content_type(:plain)
          return response
        else
          callback_required_response
        end
      end

      def response_opened(session)
        session.process_buffer
      end

      def format_frame(session, payload)
        raise TypeError.new("Payload must not be nil!") if payload.nil?

        # Yes, JSONed twice, there isn't a better way, we must pass
        # a string back, and the script, will be evaled() by the browser.
        "#{session.data[:callback]}(#{payload.chomp.to_json});\r\n"
      end
    end

    # This is the sender.
    class JSONPSend < SessionTransport
      register 'POST', 'jsonp_send'

      # Handler.
      def request_data(request)
        if request.content_type == "application/x-www-form-urlencoded"
          raw_data = request.data.read || empty_payload
          data = URI.decode_www_form(raw_data)

          # It always has to be d=something.
          if data && data.first && data.first.first == "d"
            data.first.last
          else
            empty_payload
          end
        else
          raw_data = request.data.read
          if raw_data && raw_data != ""
            raw_data
          else
            empty_payload
          end
        end
      end

      def continuing_response(session, request)
        response = response_class.new(request, 200)

        response.set_content_type(:plain)
        response.set_session_id(request.session_id)
        response.write("ok")
      end

      def unknown_session(request)
        raise SockJS::HttpError.new(404, "Session is not open!") { |response|
          response.set_content_type(:plain)
          response.set_session_id(request.session_id)
        }
      end

      def empty_payload
        raise SockJS::HttpError.new(500, "Payload expected.") { |response|
          response.set_content_type(:html)
        }
      end
    end
  end
end
