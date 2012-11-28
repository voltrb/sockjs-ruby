# encoding: utf-8
#
require 'alter_ego'
require 'sockjs/protocol'
require 'sockjs/callbacks'

module SockJS
  class Session
    include AlterEgo
    include CallbackMixin

    state :fresh, :default => true do
      on_enter do
        self.transport = nil
      end

      handle(:disconnect_expired){}

      handle :receive_request do |request, transport|
        @transport = transport
        data = transport.request_data(request)
        SockJS.debug "Building an opening response..."
        @response = transport.opening_response(self, request)
        transition_to(:opening)
        @response
      end

      handle :finish do
        #No response to close up
      end
    end

    state :opening do
      on_enter do
        handle_send_data(Protocol::OpeningFrame.instance)

        set_timer
        set_alive_checker
      end

      handle :disconnect_expired do
      end

      handle :check_status do
        transition_to :open
        @transport.session_opened(self)
      end
      handle :finish do
        #No response to close up
      end
    end

    state :idle do
      on_enter do
        finish_response
      end

      handle :receive_request do |request, transport|
        data = transport.request_data(request)
        SockJS.debug "Building a continuing response..."
        response = @response = transport.continuing_response(self, request)
        transition_to(:open)
        receive_message(request, data)
        @transport.session_continues(self)
        response
      end

      handle :close do |status, message|
        close_session(status || 3000, message || "Go away!")
      end

      handle :finish do
        #No response to close up
      end

      transition :to => :closing
      transition :to => :open
    end

    state :open do
      on_enter do
        execute_callback(:open, self)
        set_heartbeat_timer
      end

      handle(:check_status){}
      handle :process_buffer, :handle_process_buffer
      handle :send_data, :handle_send_data

      handle :finish do
        send_data(outbox_frame)
      end

      handle :close do |status, message|
        close_session(status || 3000, message || "Go away!")
      end
      handle :send_heartbeat do
        send_data(Protocol::HeartbeatFrame.instance)
      end

      handle :disconnect_expired do
        close
      end

      handle :close_response do
        SockJS.debug "close_response: clearing response and transport."
        transition_to(:idle)
      end

      transition :to => :idle
      transition :to => :waiting, :on => :wait
      transition :to => :closing
    end

    state :waiting do
      on_enter do
        run_user_app(response)
        set_timer
        init_periodic_timer
      end

      handle(:disconnect_expired){}
      handle :send_data, :handle_send_data
      #XXX when do we start the heartbeat timer?
      handle :send_heartbeat do
        send_data(Protocol::HeartbeatFrame.instance)
      end

      handle :finish do
        send_data(outbox_frame)
      end

      handle :close_response do
        SockJS.debug "close_response: clearing response and transport."
        transition_to(:idle)
      end

      handle :wait do
        SockJS.debug "Session#wait: another connection still open"
        close(2010, "Another connection still open")
      end
    end

    #XXX State names are, IMO, confusing. Consider "closed" and "finalized"
    state :closing do
      on_enter do
        finish
        cancel_timers
        reset_close_timer
      end

      handle :close do
        cancel_timers
      end

      handle :send_data do
        handle_send_data(@closing_frame)
      end

      handle :finish do
        send_data(@closing_frame)
        finish_response
      end

      transition :to => :closed, :on => :mark_to_be_garbage_collected do
        SockJS.debug "Closing the session"
      end

      handle(:disconnect_expired){}
    end

    state :closed do
      handle(:disconnect_expired){}
      handle :close do
        :cancel_timers
      end
    end

    request_filter :new_state => :opening do
      !(@transport.nil? or @response.nil?)
    end

    request_filter :new_state => :open do
      !@transport.nil?
    end

    request_filter :new_state => :waiting do
      !@response.nil?
    end

    request_filter :new_state => :closing do
      !(@closing_frame.nil?)
    end

    attr_accessor :disconnect_delay, :interval
    attr_reader :transport, :response, :outbox, :closing_frame, :data

    def initialize(callbacks)
      @callbacks = callbacks
      @disconnect_delay = 5 # TODO: make this configurable.
      @received_messages = []
      @outbox = []
      @total_sent_content_length = 0
      @interval = 0.1
      @closing_frame = nil
      @data = {}
    end

    def handle_send_data(frame)
      data = @transport.format_frame(self, frame.to_s)

      @total_sent_content_length += data.bytesize

      @response.write(data)
    end

    def send_transmit_queue
      send_data(Protocol::ArrayFrame.new(@outbox))
      clear_transmit_queue
    end

    def clear_transmit_queue
      @outbox.clear
    end

    def send(*messages)
      return if messages.empty?
      push_messages(*messages)
      @transport.data_queued(self)
    end

    def push_messages(*messages)
      @outbox += messages
    end

    def outbox_frame
      Protocol::ArrayFrame.new(@outbox)
      #XXX empty @outbox?
    end

    #Use in place of finish(true) for "no_content"
    def finish_response
      @response.finish if @response
      @response = nil
    end

    # All incoming data is treated as incoming messages,
    # either single json-encoded messages or an array
    # of json-encoded messages, depending on transport.
    def receive_message(request, data)
      reset_timer do
        check_status

        messages = parse_json(data)
        process_messages(*messages) unless messages.empty?
      end
    end

    def process_messages(*messages)
      @received_messages.push(*messages)
    end
    protected :process_messages

    def after_app_run
    end

    def app_response
      SockJS.debug "Processing buffer using #{@transport.class}"
      check_status

      raise @error if @error

      @received_messages.each do |message|
        SockJS.debug "Executing app with message #{message.inspect}"
        self.execute_callback(:buffer, self, message)
      end
      @received_messages.clear

      self.after_app_run
    end

    def handle_process_buffer(timer_reset = true)
      if timer_reset
        reset_timer {
          app_response
        }
      else
        app_response
      end

      create_response
    rescue SockJS::NoContentError => error
      set_heartbeat_timer
    rescue SockJS::CloseError => error
      Protocol::ClosingFrame.new(error.status, error.message)
    end

    def create_response
      if @outbox.empty?
        nil
      else
        result = outbox_frame
        @outbox.clear
        result
      end
    end

    # Set the internal state to closing
    def close_session(status = 3000, message = "Go away")
      @closing_frame = Protocol::ClosingFrame.new(status, message)
      transition_to(:closing)
    end

    def cancel_timers
      if @periodic_timer
        @periodic_timer.cancel
        @periodic_timer = nil
      end

      if @alive_checker
        @alive_checker.cancel
        @alive_checker = nil
      end
    end

    def on_close
      SockJS.debug "The connection has been closed on the client side (current status: #{@status})."
      close_session(1002, "Connection interrupted")
    end

    def max_permitted_content_length
      @max_permitted_content_length ||= ($DEBUG ? 4096 : 128_000)
    end

    def run_user_app(response)
      SockJS.debug "Executing user's SockJS app"
      frame = process_buffer(false)
      send_data(frame) if frame and not frame.is_a? Protocol::ClosingFrame
      SockJS.debug "User's SockJS app finished"
    end

    # Periodic timer runs the user app if it receives some
    # messages in the meantime. Also, it closes the response
    # if maximal content length is exceeded.
    def init_periodic_timer
      @periodic_timer = EM::PeriodicTimer.new(interval) do
        SockJS.debug "Tick: #{@status}, #{@outbox.inspect}"

        unless @received_messages.empty?
          run_user_app(response)

          if @total_sent_content_length >= max_permitted_content_length
            SockJS.debug "Maximal permitted content length exceeded, closing the connection."

            finish_response

            @periodic_timer.cancel

            transition_to(:closed)
          else
            SockJS.debug "Permitted content length: #{@total_sent_content_length} of #{max_permitted_content_length}"
          end
        end
      end
    end

    protected
    def parse_json(data)
      if data.empty?
        return []
      end

      JSON.parse(data)
    rescue JSON::ParserError => error
      raise SockJS::InvalidJSON.new(500, "Broken JSON encoding.")
    end

    # Disconnect timer to close the response after longer inactivity.
    def set_timer
      SockJS.debug "Setting @disconnect_timer to #{@disconnect_delay}"
      @disconnect_timer ||=
        begin
          EM::Timer.new(@disconnect_delay) do
            SockJS.debug "#{@disconnect_delay} has passed, firing @disconnect_timer"
            @periodic_timer.cancel if @periodic_timer
            @alive_checker.cancel if @alive_checker

            disconnect_expired
          end
        end
    end

    # Alive checker checks
    def set_alive_checker
      SockJS.debug "Setting alive_checker."
      @alive_checker ||=
        begin
          EM::PeriodicTimer.new(1) do
            if @transport && @response && ! @response.body.closed?
              begin
                if @response.due_for_alive_check
                  SockJS.debug "Checking if still alive"
                  # If the following statement fails, we know
                  # that the connection has been interrupted.
                  @response.write(@transport.empty_string)
                end
              rescue Exception => error
                puts "==> "
                SockJS.debug error
                puts "==> "
                on_close
                @alive_checker.cancel
              end
            else
              puts "~ [TODO] Not checking if still alive, why?"
              puts "Status: #{@status} (response.body.closed: #{@response.body.closed?})\nSession class: #{self.class}\nTransport class: #{@transport.class}\nResponse: #{@response.to_s}\n\n"
            end
          end
        end
    end

    def reset_timer(&block)
      SockJS.debug "Cancelling @disconnect_timer"
      if @disconnect_timer
        @disconnect_timer.cancel
        @disconnect_timer = nil
      end

      block.call if block

      set_timer
    end

    def reset_close_timer
      if @close_timer
        SockJS.debug "Cancelling @close_timer"
        @close_timer.cancel
      end

      SockJS.debug "Setting @close_timer to #{@disconnect_delay}"

      # Close timer is to mark the session as garbage and
      # effectively destroy it. At the time it's already closed.
      @close_timer = EM::Timer.new(@disconnect_delay) do
        SockJS.debug "@close_timer fired"
        @periodic_timer.cancel if @periodic_timer
        self.mark_to_be_garbage_collected
      end
    end

    # Heartbeats to make sure nothing times out.
    def set_heartbeat_timer
      # Cancel @disconnect_timer.
      SockJS.debug "Cancelling @disconnect_timer as we're about to send a heartbeat frame in 25s."
      @disconnect_timer.cancel if @disconnect_timer
      @disconnect_timer = nil

      @alive_checker.cancel if @alive_checker

      # Send heartbeat frame after 25s.
      @heartbeat_timer ||= EM::Timer.new(25) do
        # It's better as we know for sure that
        # clearing the buffer won't change it.
        SockJS.debug "Sending heartbeat frame."
        begin
          send_heartbeat
        rescue Exception => error
          # Nah these exceptions are OK ... let's figure out when they occur
          # and let's just not set the timer for such cases in the first place.
          SockJS.debug "Exception when sending heartbeat frame: #{error.inspect}"
        end
      end
    end
  end

  class SessionWitchCachedMessages < Session
    def send(*messages)
      @outbox += messages
    end

    def run_user_app(response)
      SockJS.debug "Executing user's SockJS app"
      frame = process_buffer(false)
      # self.send_data(frame) if frame and not frame.match(/^c\[\d+,/)
      SockJS.debug "User's SockJS app finished"
    end

    def send_data(frame)
      super(frame)

      close_response
    end

    def set_alive_checker
    end

    alias_method :after_app_run, :finish
  end

  class WebSocketSession < Session
    attr_accessor :ws
    undef :response

    def send_data(frame)
      if frame.nil?
        raise TypeError.new("Frame must not be nil!")
      end

      unless frame.empty?
        SockJS.debug "@ws.send(#{frame.inspect})"
        @ws.send(frame)
      end
    end

    def after_app_run
      return super unless self.closing?

      after_close
    end

    def after_close
      SockJS.debug "after_close: calling #finish"
      finish

      SockJS.debug "after_close: closing @ws and clearing @transport."
      @ws.close
      @transport = nil
    end

    def set_alive_checker
    end
  end
end
