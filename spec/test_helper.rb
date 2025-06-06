# spec/test_helper.rb
# frozen_string_literal: true

require "simplecov"

SimpleCov.start do
  add_filter "/spec/"
end

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "can_messenger"

require "rspec"
