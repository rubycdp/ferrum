# frozen_string_literal: true

require "bundler/setup"
require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new("test") do |t|
  t.ruby_opts = "-w"
  t.rspec_opts = "--format=documentation" if ENV["CI"]
end

task default: :test

begin
  require "yard"
  YARD::Rake::YardocTask.new
rescue LoadError
  # nop
end
