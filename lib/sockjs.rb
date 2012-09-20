# encoding: utf-8

require "eventmachine"
require "forwardable"
require 'sockjs/callbacks'
require "sockjs/version"
require 'sockjs/connection'

def Time.timer(&block)
  - (Time.now.tap { yield } - Time.now)
end

module SockJS
  def self.debug!
    @debug = true
  end

  def self.debug?
    @debug
  end

  def self.puts(message)
    if self.debug?
      STDERR.puts(message)
    end
  end

  def self.debug(message)
    self.puts("~ #{message}")
  end

  class CloseError < StandardError
    attr_reader :status, :message
    def initialize(status, message)
      @status, @message = status, message
    end
  end

  class HttpError < StandardError
    attr_reader :status, :message

    # TODO: Refactor to (status, message, &block)
    def initialize(*args, &block)
      @message = args.last
      @status = (args.length >= 2) ? args.first : 500
      @block = block
    end

    def to_response(adapter, request)
      adapter.response(request, self.status) do |response|
        response.set_content_type(:plain)
        @block.call(response) if @block
        response.write(self.message) if self.message
      end
    end
  end

  class InvalidJSON < HttpError
  end
end
