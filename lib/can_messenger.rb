# lib/can_messenger.rb
# frozen_string_literal: true

require_relative "can_messenger/version"
require_relative "can_messenger/constants"
require_relative "can_messenger/messenger"
require_relative "can_messenger/dbc"

# Public namespace for CAN messaging, transport adapters, and DBC encoding/decoding.
# Requiring "can_messenger" loads these components together.
module CanMessenger
  # Library-specific error type available to callers and adapter extensions.
  class Error < StandardError; end
end
