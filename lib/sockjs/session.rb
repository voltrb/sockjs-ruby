# encoding: utf-8
#
require 'meta-state'
require 'sockjs/protocol'
require 'sockjs/callbacks'

module SockJS
  class Session < MetaState::Machine
    include CallbackMixin

    class Consumer
      def initialize(response, transport)
        @response = response
        @transport = transport
      end
      attr_reader :response, :transport

      def heartbeat
        transport.heartbeat_frame(reponse)
      end

      def messages(items)
        transport.messages_frame(response, items) unless items.empty?
      end

      def closing(status, message)
        transport.closing_frame(status, message)
      end

      #XXX Still not sure what this is *FOR*
      def check_alive
        if !@response.body.closed?
          if @response.due_for_alive_check
            SockJS.debug "Checking if still alive"
            @response.write(@transport.empty_string)
          else
            puts "~ [TODO] Not checking if still alive, why?"
            puts "Status: #{@status} (response.body.closed: #{@response.body.closed?})\nSession class: #{self.class}\nTransport class: #{@transport.class}\nResponse: #{@response.to_s}\n\n"
          end
        end
      end
    end

    state :Detached do
      def on_enter
        @consumer = nil
        clear_all_timers
        set_disconnect_timer
      end

      def attach_consumer(response, transport)
        @consumer = Consumer.new(response, transport)
        transition_to :attached
      end

      def send(*messages)
        @outbox += messages
      end

      def close(status = nil, message = nil)
        @close_status = status
        @close_message = message
        transition_to(:closed)
      end
    end

    state :Attached do
      def on_enter
        @consumer.messages(@outbox)
        @outbox.clear
        clear_all_timers
        set_heartbeat_timer
      end

      def attach_consumer(response, transport)
        SockJS.debug "Session#attach_consumer: another connection still open"
        transport.closing_frame(response, 2010, "Another connection still open")
      end

      def detach_consumer
        transition_to :detached
      end

      def send(*messages)
        @consumer.messages(messages)
      end

      def send_heartbeat
        @consumer.heartbeat
      end

      def close(status = nil, message = nil)
        @close_status = status
        @close_message = message
        @consumer.closing(@close_status, @close_message)
        @consumer = nil
        transition_to(:closed)
      end
    end

    state :Closed do
      def on_enter
        @close_status ||= 3000
        @close_message ||= "Go away!"
        clear_all_timers
        set_close_timer
      end

      def attach_consumer(response, transport)
        transport.closing_frame(response, @close_status, @close_message)
      end
    end


    #### Client Code interface

    # All incoming data is treated as incoming messages,
    # either single json-encoded messages or an array
    # of json-encoded messages, depending on transport.
    def receive_message(data)
      clear_timer(:disconnect)

      messages = parse_json(data)
      unless messages.empty?
        @received_messages.push(*messages)
      end

      EM.next_tick do
        run_user_app
      end

      set_disconnect_timer
    end

    def run_user_app
      unless @received_messages.empty?
        reset_heartbeat_timer

        SockJS.debug "Executing user's SockJS app"

        raise @error if @error

        @received_messages.each do |message|
          SockJS.debug "Executing app with message #{message.inspect}"
          self.execute_callback(:buffer, self, message)
        end
        @received_messages.clear

        after_app_run

        SockJS.debug "User's SockJS app finished"

        if @total_sent_content_length >= max_permitted_content_length
          SockJS.debug "Maximum content length exceeded, closing the connection."

          close(3000, "Maximum content length exceeded")
        else
          SockJS.debug "Permitted content length: #{@total_sent_content_length} of #{max_permitted_content_length}"
        end
      end
    rescue SockJS::CloseError => error
      Protocol::ClosingFrame.new(error.status, error.message)
    end

    def after_app_run
    end


    attr_accessor :disconnect_delay, :interval
    attr_reader :transport, :response, :outbox, :closing_frame, :data

    def initialize(callbacks)
      super()

      debug_with do |msg|
        SockJS::debug(msg)
      end

      @callbacks = callbacks
      @disconnect_delay = 5 # TODO: make this configurable.
      @received_messages = []
      @outbox = []
      @total_sent_content_length = 0
      @interval = 0.1
      @closing_frame = nil
      @data = {}
      @alive = true
      @timers = {}
    end

    def alive?
      !!@alive
    end

    #XXX This is probably important - need to examine this case
    def on_close
      SockJS.debug "The connection has been closed on the client side (current status: #{@status})."
      close_session(1002, "Connection interrupted")
    end

    def max_permitted_content_length
      @max_permitted_content_length ||= ($DEBUG ? 4096 : 128_000)
    end

    def parse_json(data)
      if data.empty?
        return []
      end

      JSON.parse(data)
    rescue JSON::ParserError => error
      raise SockJS::InvalidJSON.new(500, "Broken JSON encoding.")
    end

    #Timers:
    #"alive_checker" - need to check spec.  Appears to check that response is
    #live.  Premature?
    #
    #"disconnect" - expires and closes the session - time without a consumer
    #
    #"close" - duration between closed and removed from management
    #
    #"heartbeat" - periodic for hb frame

    #Timer actions:

    def disconnect_expired
      SockJS.debug "#{@disconnect_delay} has passed, firing @disconnect_timer"
      close
    end

    #XXX Remove?  What's this for?
    def check_response_alive
      if @consumer
        begin
          @consumer.check_alive
        rescue Exception => error
          puts "==> "
          SockJS.debug error
          puts "==> "
          on_close
          @alive_checker.cancel
        end
      else
        puts "~ [TODO] Not checking if still alive, why?"
      end
    end

    def heartbeat_triggered
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

    #Timer machinery

    def set_timer(name, type, delay, &action)
      @timers[name] ||=
        begin
          SockJS.debug "Setting timer: #{name} to expire after #{delay}"
          type.new(delay, &action)
        end
    end

    def clear_timer(name)
      @timers[name].cancel unless @timers[name].nil?
      @timers.delete(name)
    end

    def clear_all_timers
      @timers.values.each do |timer|
        timer.cancel
      end
      @timers.clear
    end


    def set_alive_timer
      set_timer(:alive_check, EM::PeriodicTimer, 1) do
        check_response_alive
      end
    end

    def reset_alive_timer
      clear_timer(:alive_check)
      set_alive_timer
    end

    def set_heartbeat_timer
      clear_timer(:disconnect)
      clear_timer(:alive)
      set_timer(:heartbeat, EM::PeriodicTimer, 25) do
        heartbeat_triggered
      end
    end

    def reset_heartbeat_timer
      clear_timer(:heartbeat)
      set_heartbeat_timer
    end

    def set_disconnect_timer
      set_timer(:disconnect, EM::Timer, @disconnect_delay) do
        disconnect_expired
      end
    end

    def reset_disconnect_timer
      clear_timer(:disconnect)
      set_disconnect_timer
    end

    def set_close_timer
      set_timer(:close, EM::Timer, @disconnect_delay) do
        @alive = false
      end
    end

    def reset_close_timer
      clear_timer(:close)
      set_close_timer
    end
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
