# vim: set ft=ruby :
require 'corundum/tasklibs'

module Corundum
  Corundum::register_project(__FILE__)

  core = Core.new

  core.in_namespace do
    sanity = GemspecSanity.new(core)
    QuestionableContent.new(core) do |dbg|
      dbg.words = %w{p debugger}
    end
    rspec = RSpec.new(core)
    cov = SimpleCov.new(core, rspec) do |cov|
      cov.threshold = 70
    end

    gem = GemBuilding.new(core)
    cutter = GemCutter.new(core,gem)
    email = Email.new(core)
    vc = Git.new(core) do |vc|
      vc.branch = "master"
    end

    yd = YARDoc.new(core)

    docs = DocumentationAssembly.new(core, yd, rspec, cov)

    pages = GithubPages.new(docs)
  end
end

task :default => [:release, :publish_docs]


# Get list of all the tests in format for TODO.todo.

task :unpack_tests do
  version = "0.2.1"

  tests = {}
  File.foreach("protocol/sockjs-protocol-#{version}.py").each_with_object(tests) do |line, buffer|
    if line.match(/class (\w+)\(Test\)/)
      buffer[$1] = Array.new
    elsif line.match(/def (\w+)/)
      if buffer.keys.last
        buffer[buffer.keys.last] << $1
      end
    end
  end

  require "yaml"
  puts tests.to_yaml
end
