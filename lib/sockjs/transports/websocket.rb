# encoding: utf-8

require "sockjs/transports/raw_websocket"

module SockJS
  module Transports
    class WebSocket < SessionTransport
      include WebSocketHandling
      extend Forwardable

      register 'GET', 'websocket'

      def disabled?
        !options[:websocket]
      end

      def buffer_class
        Buffer
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
    end
  end
end
