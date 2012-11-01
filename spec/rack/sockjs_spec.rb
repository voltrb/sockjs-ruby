require 'spec_helper'

require 'rack/sockjs'

describe Rack::SockJS do
  let :rack_app do
    Rack::SockJS.new do |connection|

    end
  end

  let :router do
    rack_app.routing
  end

  let :request do
    Rack::Request.new(env)
  end

  let :routing do
    router.recognize(request)
  end

  let :route do
    routing[0]
  end

  let :matches do
    routing[1]
  end

  let :params do
    routing[2]
  end

  describe "websockets" do
    let :env do
      {
        'REQUEST_METHOD' => 'GET',
        'PATH_INFO' => '/000/742088cb-1c02-46be-bfee-2d845405ae75/websocket'
      }
    end

    it "should route to websockets" do
      route.app.should be_an_instance_of(::SockJS::Transports::WebSocket)
    end
  end

end
