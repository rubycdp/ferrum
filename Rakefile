# frozen_string_literal: true

require "bundler/setup"
require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "./lib/rake/kill_browsers"

RSpec::Core::RakeTask.new("test")

task default: :test
