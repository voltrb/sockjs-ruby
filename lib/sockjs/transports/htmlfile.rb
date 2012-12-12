# encoding: utf-8

require "json"
require "sockjs/transport"

module SockJS
  module Transports
    class HTMLFile < ConsumingTransport
      register 'GET', 'htmlfile'

      HTML_PREFIX = <<-EOT.chomp.freeze
<!doctype html>
<html><head>
  <meta http-equiv="X-UA-Compatible" content="IE=edge" />
  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
</head><body><h2>Don't panic!</h2>
  <script>
    document.domain = document.domain;
    var c = parent.
      EOT

      HTML_POSTFIX = (<<-EOH + (" " * (1024 - HTML_PREFIX.bytesize)) + "\r\n\r\n").freeze
;
    c.start();
    function print(d) {c.message(d);};
    window.onload = function() {c.stop();};
  </script>
      EOH


      def session_opened(session)
        session.wait(response)
      end

      def setup_response(request, response)
        response.status = 200
        response.set_content_type(:html)
        response.set_no_cache
        response.set_session_id(request.session_id)

        response
      end

      def process_session(session, response)
        if response.request.callback
          response.write(HTML_PREFIX)
          response.write(response.request.callback)
          response.write(HTML_POSTFIX)
          super
        else
          raise SockJS::HttpError.new(500, '"callback" parameter required')
        end
      end

      def handle_http_error(request, error)
        response = build_response(request)
        response.status = error.status
        response.set_no_cache
        response.set_content_type(:html)

        SockJS::debug "Built error response: #{response.inspect}"
        response.write(error.message)
        response
      end

      def format_frame(response, frame)
        raise TypeError.new("Payload must not be nil!") if frame.nil?

        "<script>\nprint(#{super.to_json});\n</script>\r\n"
      end
    end
  end
end
