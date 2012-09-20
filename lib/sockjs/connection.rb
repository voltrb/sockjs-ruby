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

    def create_session(key, transport, session_class = transport.session_class)
      self.sessions[key] ||= begin
        session_class.new(open: callbacks[:session_open], buffer: callbacks[:subscribe])
      end
    end
  end
end
