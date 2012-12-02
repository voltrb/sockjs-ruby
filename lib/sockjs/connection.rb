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

    #XXX TODO: remove dead sessions as they're get_session'd, along with a
    #recurring clearout
    def sessions
      SockJS.debug "Refreshing sessions"

      if @sessions
        @sessions.delete_if do |_, session|
          unless session.alive?
            SockJS.debug "Removing closed session #{_}"
          end

          !session.alive?
        end
      else
        @sessions = {}
      end
    end

    def subscribe(&block)
      self.callbacks[:subscribe] << block
    end

    def session_open(&block)
      self.callbacks[:session_open] << block
    end

    def get_session(session_key)
      SockJS.debug "Looking up session at #{session_key.inspect}"
      sessions.fetch(session_key)
    end

    def create_session(session_key)
      SockJS.debug "Creating session at #{session_key.inspect}"
      raise "Session already exists for #{session_key.inspect}" if sessions.has_key?(session_key)
      sessions[session_key] = Session.new(open: callbacks[:session_open], buffer: callbacks[:subscribe])
    end
  end
end
