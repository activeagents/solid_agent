# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

# Two suites, two processes.
#
# test/test_helper.rb hand-rolls stand-ins for Rails, ActiveSupport::Concern,
# class_attribute and friends so the unit tests run without Rails installed.
# Its mock `Rails` constant is enough to make `require "active_agent"` fail
# outright — ActiveAgent loads its railtie whenever Rails is defined — so the
# unit harness and test/integration/, which needs a real ActiveAgent, cannot
# share a process. Separate tasks is what keeps both harnesses honest.
Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"].exclude("test/integration/**/*_test.rb")
end

namespace :test do
  desc "Run integration tests against a real ActiveAgent"
  Rake::TestTask.new(:integration) do |t|
    t.libs << "test"
    t.libs << "lib"
    t.test_files = FileList["test/integration/**/*_test.rb"]
  end
end

task default: [ :test, "test:integration" ]
