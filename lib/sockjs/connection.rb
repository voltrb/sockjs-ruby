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
      # The block is supposed to return session.
      session = sessions[session_key]

      if session
        if session.closing?
          # response.body is closed, why?
          SockJS.debug "get_session: session is closing"
          raise SessionUnavailableError.new(session)
        elsif session.open? || session.newly_created? || session.opening?
          SockJS.debug "get_session: session retrieved successfully"
          return session
          # TODO: Should be alright now, check 6aeeaf1fd69c
        elsif session.response # THIS is an utter piece of sssshhh ... of course there's a response once we open it!
          SockJS.debug "get_session: another connection still open"
          raise SessionUnavailableError.new(session, 2010, "Another connection still open")
        else
          raise "We should never get here!\nsession.status: #{session.status}, has session response: #{!! session.response}"
        end
      else
        SockJS.debug "get_session: session for #{session_key.inspect} doesn't exist."
        return nil
      end
    end

    def create_session(key, transport, session_class = transport.session_class)
      self.sessions[key] ||= begin
        session_class.new(open: callbacks[:session_open], buffer: callbacks[:subscribe])
      end
    end
  end
end
