# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

# Two suites, two processes. Rake::TestTask forks one Ruby per task, which is
# the point: these harnesses cannot share a process.
#
# * test/ (unit) hand-rolls stand-ins for Rails and ActiveModel so the concerns
#   run with no Rails and no database.
# * test/records/ boots a real ActiveRecord on sqlite :memory:. Loading it into
#   the unit process would put a genuine ActiveRecord::Base underneath the mock
#   one, and the two disagree about everything.
#
# Splitting them is what keeps both harnesses honest — and what makes a failure
# name the harness it happened in.
Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"].exclude("test/records/**/*_test.rb")
end

namespace :test do
  desc "Run the record concerns against a real ActiveRecord on sqlite"
  Rake::TestTask.new(:records) do |t|
    t.libs << "test"
    t.libs << "lib"
    t.test_files = FileList["test/records/**/*_test.rb"]
  end
end

task default: [ :test, "test:records" ]
