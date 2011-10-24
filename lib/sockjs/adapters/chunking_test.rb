# encoding: utf-8

require_relative "../adapter"

module SockJS
  module Adapters
    class ChunkingTestOptions < Adapter
      # Settings.
      self.prefix  = "chunking_test"
      self.method  = "OPTIONS"
      self.filters = [:h_sid, :xhr_cors, :cache_for, :xhr_options, :expose]

      # Handler.
      def self.handle(env, options, sessions)
        year = 31536000
        time = Time.now + year

        request = Rack::Request.new(env)
        biscuit = "JSESSIONID=#{request.cookies["JSESSIONID"] || "dummy"}; path=/"
        origin  = env["HTTP_ORIGIN"] || "*"

        [204, {"Access-Control-Allow-Origin" => origin, "Access-Control-Allow-Credentials" => "true", "Allow" => "OPTIONS, POST", "Cache-Control" => "public, max-age=#{year}", "Expires" => time.gmtime.to_s, "Access-Control-Max-Age" => "1000001", "Set-Cookie" => biscuit}, Array.new]
      end
    end

    class ChunkingTestPost < ChunkingTestOptions
      self.method  = "POST"
      self.filters = [:h_sid, :xhr_cors, :expect_xhr, :chunking_test]

      # Handler.
      def self.handle(env, options, sessions)
        timeoutable = SockJS::Timeoutable.new(
          # IE requires 2KB prelude.
          0    => " " * 2048 + "h\n",
          5    => "h\n",
          25   => "h\n",
          125  => "h\n",
          625  => "h\n",
          3125 => "h\n",
        )

        [200, {"Content-Type" => "application/javascript; charset=UTF-8", "Access-Control-Allow-Origin" => "*", "Access-Control-Allow-Credentials" => "true", "Allow" => "OPTIONS, POST"}, timeoutable]
      end
    end
  end
end