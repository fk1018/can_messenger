# lib/can_messenger.rb
# frozen_string_literal: true

require_relative "can_messenger/version"
require_relative "can_messenger/messenger"
require_relative "can_messenger/dbc"

module CanMessenger
  class Error < StandardError; end
end
