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

  def self.no_debug!
    @debug = false
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

  def self.debug_exception(exception)
    self.debug(([exception.class.name, exception.message].join(": ") + exception.backtrace).join("\n"))
  end

  class CloseError < StandardError
    attr_reader :status, :message
    def initialize(status, message)
      @status, @message = status, message
    end
  end

  class HttpError < StandardError
    attr_reader :status, :message

    def initialize(status, message, &block)
      @message = message
      @status = status
      @block = block
    end

    def to_response(adapter, request)
      response = adapter.sessionless_response(request, self.status)

      response.set_content_type(:plain)
      @block.call(response) if @block
      SockJS::debug "Built error response: #{response.inspect}"
      response.write(self.message) if self.message
      response
    end
  end

  class InvalidJSON < HttpError
  end
end
