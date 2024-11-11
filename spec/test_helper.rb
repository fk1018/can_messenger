# test/test_helper.rb
# frozen_string_literal: true

require "simplecov"

SimpleCov.start do
  add_filter "/test/"   # Exclude test files from coverage results
end

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "can_messenger" # This will load `lib/can_messenger/messenger.rb`

require "rspec"
