# encoding: utf-8

require "json"
require "sockjs/transport"

module SockJS
  module Transports
    class HTMLFile < SessionTransport
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

      def opening_response(session, request)
        if request.callback
          response = response_class.new(request, 200)
          response.set_content_type(:html)
          response.set_no_cache
          response.set_session_id(request.session_id)

          response.write(HTML_PREFIX)
          response.write(request.callback)
          response.write(HTML_POSTFIX)
          response
        else
          sessionless_response(request, 500) do |response|
            response.set_content_type(:html)
            response.write('"callback" parameter required')
          end
        end
      end

      def format_frame(payload)
        raise TypeError.new("Payload must not be nil!") if payload.nil?

        "<script>\nprint(#{payload.to_json});\n</script>\r\n"
      end
    end
  end
end
