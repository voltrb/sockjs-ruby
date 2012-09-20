#!/usr/bin/env bundle exec rspec
# encoding: utf-8

require "spec_helper"

require "sockjs"
require "sockjs/session"
require "sockjs/transports/xhr"

class Session < SockJS::Session
  include ResetSessionMixin

  def set_status_for_tests(status)
    @buffer = SockJS::Buffer.new(status)
    @status = status
    self
  end
end

describe Session do
  around :each do |example|
    EM.run do
      example.run
      EM.stop
    end
  end

  let :connection do
    SockJS::Connection.new {}
  end

  let :transport do
    xprt = SockJS::Transports::XHRPost.new(connection, Hash.new)

    def xprt.send
    end

    xprt
  end

  let :request do
    FakeRequest.new
  end

  let :response do
    transport.response_class.new(request, 200)
  end

  let :buffer do
    SockJS::Buffer.new
  end

  let :session do
    sess = described_class.new({:open => []})
    sess.transport = transport
    sess.response = response
    sess.buffer = buffer
    sess
  end

  describe "#initialize(transport, callback)" do
    it "should take two arguments" do
      expect { described_class.new(1, 2) }.to_not raise_error(ArgumentError)
    end
  end

  describe "#send(data, *args)" do
    before(:each) do
      session.buffer = SockJS::Buffer.new(:open)
    end

    it "should clear the message buffer" do
      session.send("test")
      session.buffer.messages.should be_empty
    end

    it "should pass optional arguments to transport.format_frame" do
      session.send("test", test: true)
    end
  end

  describe "#finish" do
    describe "transport responds to #send" do
      it "should call transport.send"
    end

    describe "transport doesn't respond to #send" do
      it "should raise an error if there's no response assigned"
      it "should finish the response with the current buffer content"
    end
  end

  describe "#receive_message" do
    it "should change status from :opening to :open"
    it "should succeed if the message is a valid JSON-like string"
  end

  describe "#process_buffer" do
    it "should reset the timer"
    it "should cache an error"
    it "should change status from :opening to :open"
    it "should execute :buffer callback for each received message"
    it "should return a frame"
  end

  describe "#create_response(&block)" do
    it "should execute the block" do
      expect {
        session.create_response do
          raise "Test"
        end
      }.to raise_error("Test")
    end

    it "should return a frame", :pending => :valid do
      sub = session.set_status_for_tests(:open)
      ret = sub.create_response {}
      ret.should eql("a[]")
    end

    it "should return a closing frame if SockJS::CloseError occured" do
      sub = session.set_status_for_tests(:open)
      ret = sub.create_response do
        raise SockJS::CloseError.new(3000, "test")
      end
      ret.should eql("c[3000,\"test\"]")
    end
  end

  describe "#check_status" do
    before(:each) do
      @session = session.set_status_for_tests(:opening)

      def @session.callback_run
        @callback_run
      end

      def @session.callback_run=(status)
        @callback_run = status
      end

      @session.callbacks[:open] << Proc.new do |session|
        session.callback_run = true
      end
    end

    it "should execute the open callback" do
      @session.check_status
      @session.callback_run.should be_true
    end

    it "should change status fro opening to open" do
      @session.check_status
      @session.should be_open
    end

    it "should do nothing if status isn't opening" do
      @session.set_status_for_tests(:closed)

      @session.check_status
      @session.should_not be_open
      @session.callback_run.should be_false
    end
  end

  describe "#open!(*args)" do
    it "should change status to opening" do
      @session = session
      @session.open!
      @session.should be_opening
    end

    it "should call session.set_timer" do
      @session = session
      @session.should_receive(:set_timer)
      @session.open!
    end

    it "should open the buffer", :pending => :valid do
      @session = session
      @session.open!
      @session.buffer.to_frame.should eql("o")
    end

    it "should call the session.finish method" do
      @session = session.set_status_for_tests(:open)
      @session.should_receive(:finish)

      @session.close
    end
  end

  describe "#close(status, message)" do
    it "should take either status and message or just a status or no argument at all" do
      -> { session.close }.should_not raise_error(ArgumentError)
      -> { session.close(3000) }.should_not raise_error(ArgumentError)
      -> { session.close(3000, "test") }.should_not raise_error(ArgumentError)
    end

    it "should fail if the user is trying to close a newly created instance" do
      -> { session.close }.should raise_error(RuntimeError)
    end

    it "should set status to closing" do
      @session = session.set_status_for_tests(:open)
      def @session.reset_close_timer; end
      @session.close
      @session.should be_closing
    end

    it "should set frame to the close frame" do
      @session = session.set_status_for_tests(:open)
      @session.close
      @session.buffer.to_frame.should eql("c[3000,\"Go away!\"]")
    end

    it "should set pass the exit status to the buffer" do
      @session = session.set_status_for_tests(:open)
      @session.close
      @session.buffer.to_frame.should match(/c\[3000,/)
    end

    it "should set pass the exit message to the buffer" do
      @session = session.set_status_for_tests(:open)
      @session.close
      @session.buffer.to_frame.should match(/"Go away!"/)
    end

    it "should call the session.finish method" do
      @session = session.set_status_for_tests(:open)
      @session.should_receive(:finish)

      @session.close
    end
  end

  describe "#newly_created?" do
    it "should return true after a new session is created" do
      session.should be_newly_created
    end

    it "should return false after a session is open" do
      session.open!
      session.should_not be_newly_created
    end
  end

  describe "#opening?" do
    it "should return false after a new session is created" do
      session.should_not be_opening
    end

    it "should return true after a session is open" do
      session.open!
      session.should be_opening
    end
  end

  describe "#open?" do
    it "should return false after a new session is created" do
      session.should_not be_open
    end

    it "should return true after a session is open" do
      session.open!
      session.check_status
      session.should be_open
    end
  end

  describe "#closing?" do
    before do
      @session = session

      def @session.reset_close_timer
      end
    end

    it "should return false after a new session is created" do
      @session.should_not be_closing
    end

    it "should return true after session.close is called" do
      @session.set_status_for_tests(:open)

      @session.close
      @session.should be_closing
    end
  end

  describe "#closed?" do
    it "should return false after a new session is created" do
      session.should_not be_closed
    end

    it "should return true after session.close is called" do
      @session = session.set_status_for_tests(:open)
      @session.should_not be_closed

      @session.close
      @session.should be_closed
    end
  end
end




class SessionWitchCachedMessages < SockJS::SessionWitchCachedMessages
  include ResetSessionMixin
end

describe SessionWitchCachedMessages do
end
