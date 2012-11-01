# encoding: utf-8

require "forwardable"
require "sockjs/faye"
require "sockjs/transport"

# Raw WebSocket url: /websocket
# -------------------------------
#
# SockJS protocol defines a bit of higher level framing. This is okay
# when the browser using SockJS-client establishes the connection, but
# it's not really appropriate when the connection is being established
# from another program. Although SockJS focuses on server-browser
# communication, it should be straightforward to connect to SockJS
# from command line or some any programming language.
#
# In order to make writing command-line clients easier, we define this
# `/websocket` entry point. This entry point is special and doesn't
# use any additional custom framing, no open frame, no
# heartbeats. Only raw WebSocket protocol.

module SockJS
  module Transports
    module WSDebuggingMixin
      def send_data(*args)
        if args.length == 1
          data = args.first
        else
          data = fix_buggy_input(*args)
        end

        SockJS.debug "WS#send #{data.inspect}"

        super(data)
      end

      def fix_buggy_input(*args)
        data = 'c[3000,"Go away!"]'
        SockJS.debug "[ERROR] Incorrect input: #{args.inspect}, changing to #{data} for now"
        return data
      end

      def close(*args)
        SockJS.debug "WS#close(#{args.inspect[1..-2]})"
        super(*args)
      end
    end

    module WebSocketHandling
      def session_class
        SockJS::WebSocketSession
      end

      def session_key(ws)
        ws.object_id.to_s
      end

      def get_session(key)
        connection.get_session(key)
      end

      def check_invalid_request_or_disabled_websocket(request)
        if not @options[:websocket]
          raise HttpError.new(404, "WebSockets Are Disabled")
        elsif request.env["HTTP_UPGRADE"].to_s.downcase != "websocket"
          raise HttpError.new(400, 'Can "Upgrade" only to "WebSocket".')
        elsif not ["Upgrade", "keep-alive, Upgrade"].include?(request.env["HTTP_CONNECTION"])
          raise HttpError.new(400, '"Connection" must be "Upgrade".')
        end
      end

      # Handlers.
      def handle(request)
        check_invalid_request_or_disabled_websocket(request)

        SockJS.debug "Upgrading to WebSockets ..."

        ws = Faye::WebSocket.new(request.env)

        ws.extend(WSDebuggingMixin)

        ws.onopen = lambda do |event|
          rescue_errors do
            self.handle_open(ws, request)
          end
        end

        ws.onmessage = lambda do |event|
          rescue_errors do
            SockJS.debug "WS data received: #{event.data.inspect}"
            self.handle_message(ws, request, event)
          end
        end

        ws.onclose = lambda do |event|
          rescue_errors do
            SockJS.debug "Closing WebSocket connection (code: #{event.code}, reason: #{event.reason.inspect})"
            self.handle_close(ws, request, event)
          end
        end
      rescue SockJS::HttpError => error
        error.to_response(self, request)
      end

      def rescue_errors
        yield
      rescue Object => error
        SockJS.debug error.inspect
      end

      def handle_open(ws, request)
        SockJS.debug "Opening WS connection."
        # Here, the session_id is not important at all,
        # it's all about the actual connection object.
        session = connection.create_session(ws.object_id.to_s, self)
        session.ws = ws
        session.buffer = buffer_class.new # This is a hack for the bloody API. Rethinking and refactoring required!
        session.transport = self

        # Send the opening frame.
        session.open!
        session.buffer = buffer_class.new(:open)
        session.check_status

        session.process_buffer # Run the app (connection.session_open hook).
      end

      # Close the connection without sending the closing frame.
      def handle_close(ws, request, event)
        SockJS.debug "Closing WS connection."
        session = get_session(session_key(ws))
        session.close if session
      rescue SockJS::SessionUnavailableError
        SockJS.debug "Session unavailable - assuming server app closed the session already"
        #Not really a problem - we assume that the user app closed the session
      end

      def format_frame(payload)
        raise TypeError.new("Payload must not be nil!") if payload.nil?

        payload
      end
    end

    class RawWebSocket < Transport
      include WebSocketHandling

      register 'GET', 'websocket'

      def buffer_class
        RawBuffer
      end

      # Run the app. Messages shall be send
      # without frames. This might need another
      # buffer class or another session class.
      def handle_message(ws, request, event)
        message = [event.data].to_json

        session = get_session(session_key(ws))

        # Unlike other transports, the WS one is supposed to ignore empty messages.
        unless message.empty?
          SockJS.debug "WS message received: #{message.inspect}"
          session.receive_message(request, message)

          # Send encoded messages in an array frame.
          messages = session.process_buffer
          if messages && messages.start_with?("a[") # We don't have any framing, this is obviously utter bollocks
            SockJS.debug "Messages to be sent: #{messages.inspect}"
            session.send_data(messages)
          end
        end
      rescue SockJS::InvalidJSON => error
        # @ws.send(error.message) # TODO: frame it ... although ... is it required? The tests do pass, but it would be inconsistent if we'd send it for other transports and not for WS, huh?
        ws.close # Close the connection abruptly, no closing frame.
      end

    end
  end
end
