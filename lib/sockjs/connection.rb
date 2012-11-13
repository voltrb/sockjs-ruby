require 'sockjs'
require 'sockjs/callbacks'

module SockJS
  class Connection
    include CallbackMixin

    def initialize(&block)
      self.callbacks[:open] << block
      self.status = :not_connected

      self.execute_callback(:open, self)
    end

    def sessions
      SockJS.debug "Refreshing sessions"

      if @sessions
        @sessions.delete_if do |_, session|
          if session.closed?
            SockJS.debug "Removing closed session #{_}"
          end

          session.closed?
        end
      else
        @sessions = Hash.new
      end
    end

    def subscribe(&block)
      self.callbacks[:subscribe] << block
    end

    def session_open(&block)
      self.callbacks[:session_open] << block
    end

    # There's a session:
    #   a) It's closing -> Send c[3000,"Go away!"] AND END
    #   b) It's open:
    #      i) There IS NOT any consumer -> OK. AND CONTINUE
    #      i) There IS a consumer -> Send c[2010,"Another con still open"] AND END
    def get_session(session_key)
      SockJS.debug "Looking up session at #{session_key.inspect}"
      sessions[session_key] ||=
        begin
          SockJS.debug "get_session: session for #{session_key.inspect} doesn't exist.  Creating..."
          Session.new(open: callbacks[:session_open], buffer: callbacks[:subscribe])
        end
    end
  end
end
