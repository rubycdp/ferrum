# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new("test") do |t|
  t.ruby_opts = "-w"
end

task default: :test
