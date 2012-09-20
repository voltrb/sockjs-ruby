#!/usr/bin/env bundle exec rspec
# encoding: utf-8

require "spec_helper"

require "sockjs"
require "sockjs/transports/htmlfile"

describe SockJS::Transports::HTMLFile do
  around :each do |example|
    EM.run {
      example.run
      EM.stop
    }
  end

  it_should_match_path  "server/session/htmlfile"
  it_should_have_method "GET"
  transport_handler_eql "a/b/htmlfile", "GET"

  describe "#handle(request)" do
    let(:transport) do
      described_class.new(SockJS::Connection.new {}, Hash.new)
    end

    let(:request) do
      @request ||= begin
        request = FakeRequest.new
        request
      end
    end

    let(:response) do
      def transport.try_timer_if_valid(*)
      end

      transport.handle(request)
    end

    context "with callback specified" do
      let(:request) do
        @request ||= FakeRequest.new.tap do |request|
          request.callback = "clbk"
          request.path_info = '/a/b/htmlfile'
        end
      end

      it "should respond with HTTP 200" do
        response.status.should eql(200)
      end

      it "should respond with HTML MIME type" do
        response.headers["Content-Type"].should match("text/html")
      end

      it "should disable caching" do
        response.headers["Cache-Control"].should eql("no-store, no-cache, must-revalidate, max-age=0")
      end

      it "should return HTML wrapper in the body" do
        response.chunks.find{|chunk| chunk =~ (/document.domain = document.domain/)}.should_not be_nil
      end

      it "should have at least 1024 bytes"
      it "should replace {{ callback }} with the actual callback name"
    end

    context "without callback specified" do
      it "should respond with HTTP 500" do
        response.status.should eql(500)
      end

      it "should respond with HTML MIME type" do
        response.headers["Content-Type"].should match("text/html")
      end

      it "should return error message in the body" do
        response # Run the handler.
        response.chunks.last.should match(/"callback" parameter required/)
      end
    end
  end

  describe "#format_frame(payload)" do
    it "should format payload"
  end
end
