# encoding: utf-8

require "sockjs/transports/raw_websocket"

module SockJS
  module Transports
    class WebSocket < SessionTransport
      include WebSocketHandling
      extend Forwardable

      register 'GET', %r{/websocket}

      def disabled?
        !options[:websocket]
      end

      def handle_message(ws, request, event)
        message = event.data

        session = get_session(session_key(ws))

        # Unlike other transports, the WS one is supposed to ignore empty messages.
        unless message.empty?
          message = "[#{message}]" unless message.start_with?("[")
          SockJS.debug "WS message received: #{message.inspect}"
          session = self.get_session { |sessions| sessions[@ws.object_id.to_s] }
          session.receive_message(request, message)

          # Run the user app.
          session.process_buffer(false)
        end
      rescue SockJS::SessionUnavailableError
        SockJS.debug "Session is already closing"
      rescue SockJS::InvalidJSON => error
        # @ws.send(error.message) # TODO: frame it ... although ... is it required? The tests do pass, but it would be inconsistent if we'd send it for other transports and not for WS, huh?
        @ws.close # Close the connection abruptly, no closing frame.
      end

      # There are two distinct situations when this handler will be called:
      #
      # 1) User app closes the response.
      # 2) Client closes the response
      #
      # In either case, this is called AFTER the actual connection is closed
      # (@ws.close), so there is not much we can do, only to mark the session
      # as terminated and delete it after the 5s timeout.
      #
      # Furthemore current API doesn't make it possible to get session
      #
      def handle_close(ws, request, event)
        SockJS.debug "WebSocket#handle_close"
      #   SockJS.debug "Closing WS connection."
      #
      #   # If it's the user app who closed
      #   # the response, we won't ever get
      #   # to pass this point as we'll get
      #   # SessionUnavailableError.
      #   self.get_session(request.path_info)
      # rescue SockJS::SessionUnavailableError => error
      #   # TODO: Set status is necessary(?)
      #   # error.session
      end
    end
  end
end
