require 'sockjs/transports/xhr'
require 'sockjs/examples/protocol_conformance_test'

describe SockJS::Transports::XHRPost do
  let :session_key do
    (1..7).map{ rand(256) }.pack("C*").unpack("H*").first
  end

  let :url_base do
    '/echo/000/' + session_key
  end

  let :protocol_version do
    "0.2.1"
  end

  let :options do
    {sockjs_url: "http://cdn.sockjs.org/sockjs-#{protocol_version}.min.js"}
  end

  let :input_stream do
    StringIO.new
  end

  let :errors_stream do
    StringIO.new
  end

  let :env do
    {
      "REQUEST_METHOD" => "",
      "SCRIPT_NAME" => "",
      "PATH_INFO" => "",
      "QUERY_STRING" => "",
      "SERVER_NAME" => "",
      "SERVER_PORT" => "",
      "rack.version" => [1,1],
      "rack.url_scheme" => "http",
      "rack.input" => input_stream,
      "rack.errors" => errors_stream,
      "rack.multithread" => false,
      "rack.multiprocess" => false,
      "rack.run_once" => true,
    }
  end

  let :app do
    SockJS::Examples::ProtocolConformanceTest.build_app(options)
  end

  let :thin_async_signal do
    [-1, {}, []]
  end

  def env_callbacks(env, chunks)
    env.merge!(
      "async.callback" => (proc do |status, headers, body|
        body.each do |chunk|
          next if chunk == "0\r\n\r\n"
          chunks << chunk.split("\r\n").last
        end
      end),

      "async.close" => EventMachine::DefaultDeferrable.new
    )
  end

  class Ticker
    def initialize
      @beats = []
    end

    def tick(&block)
      @beats << block
    end

    def finish
      EM.run do
        EM.next_tick &((@beats).reverse.inject(proc{ EM.stop }) do |wrapped, block|
          proc do
            block.call
            EM.next_tick(&wrapped)
          end
        end)
      end
    end
  end

  it "should handle closes correctly" do
    SockJS::debug!
    ticker = Ticker.new
    chunks = []
    env2 = env.merge({"REQUEST_METHOD" => "POST", "PATH_INFO" => url_base + "/xhr"})

    ticker.tick do
      env_callbacks(env2, chunks)
      puts "Opening one"
      app.call(env2).should == thin_async_signal
    end

    ticker.tick do
      chunks.join("").should == "o\n"
      env2["async.close"].succeed
    end

    env3 = env.merge({
      "REQUEST_METHOD" => "POST",
      "PATH_INFO" => url_base + "/xhr",
      "HTTP_X_REQIDX" => "one"
    })

    one_chunks = []

    env4 = env.merge({
      "REQUEST_METHOD" => "POST",
      "PATH_INFO" => url_base + "/xhr",
      "HTTP_X_REQIDX" => "two"
    })
    two_chunks = []

    ticker.tick do
      env_callbacks(env3, one_chunks)
      app.call(env3).should == thin_async_signal

      env_callbacks(env4, two_chunks)
      app.call(env4).should == thin_async_signal
    end

    ticker.tick do
      one_chunks.join("").should == 'o\n'
      two_chunks.join("").should == 'c[2010,"Another connection still open"]\n'
    end

    ticker.finish


#        print "Reopening one"
#        r1 = POST_async(url + '/xhr', headers={'X-ReqIdx':'one'}, load=False)
#        print "Holding one"
#
#        # Can't do second polling request now.
#        print "Opening two"
#        r2 = POST(url + '/xhr', headers={'X-ReqIdx':'two'})
#        self.assertEqual(r2.body, 'c[2010,"Another connection still open"]\n')
#
#        print "Two fails"
#
#        r1.close()
#
#        print "Closing one"
#
#        # Polling request now, after we aborted previous one, should
#        # trigger a connection closure. Implementations may close
#        # the session and forget the state related. Alternatively
#        # they may return a 1002 close message.
#        print "Opening three"
#        r3 = POST(url + '/xhr')
#        self.assertTrue(r3.body in ['o\n', 'c[1002,"Connection interrupted"]\n'])

  end
end
