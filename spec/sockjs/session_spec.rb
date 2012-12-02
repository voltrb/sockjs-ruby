#!/usr/bin/env bundle exec rspec
# encoding: utf-8

require "spec_helper"

require "sockjs"
require "sockjs/session"
require "sockjs/transports/xhr"

#Comment:
#These specs came to me way to interested in the internals of Session
#Policy has got to be that any spec that fails because e.g. it wants to know
#what state Session is in is a fail.  Okay to spec that Session should be able
#to respond to message X after Y, though.

describe SockJS::Session do
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
    FakeRequest.new.tap do|req|
      req.data = ""
    end
  end

  let :response do
    transport.response_class.new(request, 200)
  end

  let :session do
    sess = described_class.new({:open => []})
    sess
  end

  let :opening_session do
    session.receive_request(request, transport)
    session
  end

  let :open_session do
    opening_session.check_status
    opening_session
  end

  let :closing_session do
    open_session.close
    open_session
  end

  let :closed_session do
    closing_session.mark_to_be_garbage_collected
    closing_session
  end

  describe "#initialize(callback)" do
    it "should take one arguments" do
      expect { described_class.new(2) }.to_not raise_error(ArgumentError)
    end
  end

  describe "#send(data, *args)" do
    it "should clear the outbound messages list" do
      open_session.send("test")
      open_session.receive_request(request, transport)
      open_session.outbox.should be_empty
    end

    it "should pass optional arguments to transport.format_frame" do
      open_session.send("test", test: true)
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

  describe "#check_status" do
    before(:each) do
      opening_session

      def session.callback_run
        @callback_run
      end

      def session.callback_run=(status)
        @callback_run = status
      end

      session.callbacks[:open] << Proc.new do |session|
        session.callback_run = true
      end
    end

    it "should execute the open callback" do
      session.check_status
      session.callback_run.should be_true
    end

    it "should do nothing if status isn't opening" do
      closed_session
      session.callback_run=false

      session.check_status
      session.callback_run.should be_false
    end
  end

  describe "opening a session" do
    it "should call session.set_timer" do
      session.should_receive(:set_timer)
      opening_session
    end

    it "should call the session.finish method" do
      SockJS::debug!
      session.should_receive(:finish)
      open_session
      session.close
    end
  end

  describe "#close(status, message)" do
    shared_examples_for "responding to #close" do
      it "should take no argument at all" do
        expect { subject.close }.not_to raise_error(ArgumentError)
      end
      it "should take just a status" do
        expect { subject.close(3000) }.not_to raise_error(ArgumentError)
      end
      it "should take status and message" do
        expect { subject.close(3000, "test") }.not_to raise_error(ArgumentError)
      end

    end

    it "should fail if the user is trying to close a newly created instance" do
      expect { session.close }.to raise_error(RuntimeError)
    end

    describe "open session" do
      subject{ open_session }

      it_should_behave_like "responding to #close"

      it "should call the session.finish method" do
        subject.should_receive(:finish)

        subject.close
      end
    end

    describe "closed session" do
      subject{ closed_session }

      it_should_behave_like "responding to #close"

      it "should not change the close frame" do
        original_close_frame = subject.closing_frame
        subject.close(3333, "Hilarity!")
        subject.closing_frame.should == original_close_frame
      end
    end
  end
end




class SessionWitchCachedMessages < SockJS::SessionWitchCachedMessages
end

describe SessionWitchCachedMessages do
end
