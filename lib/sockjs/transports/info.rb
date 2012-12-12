# encoding: utf-8

require "sockjs/transport"

module SockJS
  module Transports
    class Info
      class Get < Endpoint
        register 'GET', "info"
        # Handler.
        def setup_response(request, response)
          response.set_content_type(:json)
          response.set_access_control(request.origin)
          response.set_allow_options_post
          response.set_no_cache
          response.write(self.info.to_json)
        end

        def info
          {
            websocket: @options[:websocket],
            origins: ["*:*"], # As specified by the spec, currently ignored.
            cookie_needed: @options[:cookie_needed],
            entropy: self.entropy
          }
        end

        def entropy
          rand(1 << 32)
        end
      end

      class Options < Endpoint
        register 'OPTIONS', 'info'

        def setup_response(request, response)
          response.set_allow_options_get
          response.set_cache_control
          response.set_access_control(request.origin)
          response.set_session_id(request.session_id)
          response.write_head
        end

        def handle_request(request)
          response = build_response(request, 204)
          response.finish
          return response
        end
      end
    end
  end
end
