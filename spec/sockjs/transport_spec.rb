# encoding: utf-8

require "sockjs"
require "sockjs/transport"

describe SockJS::Transport do
  describe "CONTENT_TYPES" do
    [:plain, :html, :javascript, :event_stream].each do |type|
      it "should define #{type}" do
        described_class::CONTENT_TYPES[type].should_not be_nil
      end
    end
  end

  describe ".prefix" do
    subject do
      Class.new(described_class)
    end

    it "should have no default value" do
      subject.prefix.should be_nil
    end

    it "should be readable and writable" do
      subject.prefix = "/test"
      subject.prefix.should eql("/test")
    end

    it "should be inheritable" do
      klass = Class.new(described_class)
      klass.prefix = "/test"
      klass.prefix.should eql("/test")

      subclass = Class.new(klass)
      subclass.prefix.should eql("/test")
    end
  end

  describe ".method" do
    subject do
      Class.new(described_class)
    end

    it "should default to GET" do
      subject.method.should eql("GET")
    end

    it "should be readable and writable" do
      subject.method = "OPTIONS"
      subject.method.should eql("OPTIONS")
    end

    it "should be inheritable" do
      klass = Class.new(described_class)
      klass.method = "POST"
      klass.method.should eql("POST")

      subclass = Class.new(klass)
      subclass.method.should eql("POST")
    end
  end

  describe ".subclasses" do
    before(:all) do
      described_class.subclasses.clear
    end

    it "should add every single subclass to Transport.subclasses" do
      transport_class = Class.new(described_class)
      described_class.subclasses.should include(transport_class)
    end

    it "should add every single subclass to Transport.subclasses regardless if it's been inherited from Transport directly or from any of its subclasses" do
      transport_class = Class.new(described_class)
      described_class.subclasses.should include(transport_class)

      another_transport_class = Class.new(transport_class)
      described_class.subclasses.should include(another_transport_class)
    end
  end

  describe ".handler" do
    let(:transport_class) { Class.new(described_class) }

    it "should match the handler which is mounted on given prefix" do
      transport_class.prefix = "/test"
      described_class.handler("/test").should eql(transport_class)

      transport_class = Class.new(described_class)
      transport_class.prefix = /[^.]+\/([^.]+)\/websocket$/
      described_class.handler("/a/b/websocket").should eql(transport_class)
    end
  end
end
