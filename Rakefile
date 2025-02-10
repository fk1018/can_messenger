# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

namespace :test do
  desc "Run RSpec tests"
  RSpec::Core::RakeTask.new(:rspec) do |t|
    t.pattern = "spec/**/*_spec.rb" # Ensure it runs all spec files in the spec directory and subdirectories
  end
end

task default: %i[rubocop test:rspec]
