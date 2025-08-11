# frozen_string_literal: true

require "logger"
require_relative "adapter/socketcan"

module CanMessenger
  # Messenger
  #
  # This class provides an interface to send and receive CAN bus messages.
  # It supports sending messages with specific CAN IDs and listening for incoming messages.
  #
  # @example
  #   messenger = CanMessenger::Messenger.new(interface_name: 'can0')
  #   messenger.send_can_message(id: 0x123, data: [0xDE, 0xAD, 0xBE, 0xEF])
  #   messenger.start_listening do |message|
  #     puts "Received: ID=#{message[:id]}, Data=#{message[:data].map { |b| '0x%02X' % b }}"
  #   end
  class Messenger
    # Initializes a new Messenger instance.
    #
    # @param [String] interface_name The CAN interface to use (e.g., 'can0').
    # @param [Logger, nil] logger Optional logger for error handling and debug information.
    # @param [Symbol] endianness The endianness of the CAN ID (default: :big) can be :big or :little.
    # @return [void]
    def initialize(interface_name:, logger: nil, endianness: :big, can_fd: false, adapter: Adapter::Socketcan)
      @interface_name = interface_name
      @logger = logger || Logger.new($stdout)
      @listening = true # Control flag for listening loop
      @endianness    = endianness # :big or :little
      @can_fd        = can_fd
      @adapter = if adapter.is_a?(Class)
                   adapter.new(interface_name: interface_name, logger: @logger, endianness: endianness)
                 else
                   adapter
                 end
    end

    # Sends a CAN message by writing directly to a raw CAN socket
    #
    # @param [Integer] id The CAN ID of the message (up to 29 bits for extended IDs).
    # @param [Array<Integer>] data The data bytes of the CAN message (0 to 8 bytes).
    # @return [void]
    def send_can_message(id:, data:, extended_id: false, can_fd: nil)
      raise ArgumentError, "id and data are required" if id.nil? || data.nil?

      use_fd = can_fd.nil? ? @can_fd : can_fd

      with_socket(can_fd: use_fd) do |socket|
        frame = @adapter.build_can_frame(id: id, data: data, extended_id: extended_id, can_fd: use_fd)
        socket.write(frame)
      end
    rescue ArgumentError
      raise
    rescue StandardError => e
      @logger.error("Error sending CAN message (ID: #{id}): #{e}")
    end

    # Encodes and sends a CAN message using a DBC definition
    #
    # @param [String] message_name The message name to encode
    # @param [Hash] signals Values for each signal in the message
    # @param [CanMessenger::DBC] dbc The DBC instance used for encoding (defaults to @dbc)
    # @return [void]
    def send_dbc_message(message_name:, signals:, dbc: @dbc, extended_id: false, can_fd: nil)
      raise ArgumentError, "dbc is required" if dbc.nil?

      encoded = dbc.encode_can(message_name, signals)
      send_can_message(id: encoded[:id], data: encoded[:data], extended_id: extended_id, can_fd: can_fd)
    rescue ArgumentError
      raise
    rescue StandardError => e
      @logger.error("Error sending DBC message #{message_name}: #{e}")
    end

    # Continuously listens for CAN messages on the specified interface.
    #
    # This method listens for incoming CAN messages and applies an optional filter.
    # The filter can be a specific CAN ID, a range of IDs, or an array of IDs.
    # Only messages that match the filter are yielded to the provided block.
    #
    # @param [Integer, Range, Array<Integer>, nil] filter Optional filter for CAN IDs.
    #   Pass a single ID (e.g., 0x123), a range (e.g., 0x100..0x200), or an array of IDs.
    #   If no filter is provided, all messages are processed.
    # @yield [message] Yields each received CAN message as a hash with keys:
    #   - `:id` [Integer] the CAN message ID
    #   - `:data` [Array<Integer>] the message data bytes
    # @return [void]
    def start_listening(filter: nil, can_fd: nil, dbc: nil, &block)
      return @logger.error("No block provided to handle messages.") unless block_given?

      @listening = true

      use_fd = can_fd.nil? ? @can_fd : can_fd

      with_socket(can_fd: use_fd) do |socket|
        @logger.info("Started listening on #{@interface_name}")
        process_message(socket, filter, use_fd, dbc, &block) while @listening
      end
    end

    # Stops the listening loop by setting @listening to false.
    #
    # This method can be called from an external thread or signal handler.
    # @return [void]
    def stop_listening
      @listening = false
      @logger.info("Stopped listening on #{@interface_name}")
    end

    private

    # Opens a socket, yields it, and closes it when done.
    #
    # @yield [socket] An open CAN socket.
    # @return [void]
    def with_socket(can_fd: @can_fd)
      socket = @adapter.open_socket(can_fd: can_fd)
      return @logger.error("Failed to open socket, cannot continue operation.") if socket.nil?

      yield socket
    ensure
      socket&.close
    end

    # Processes a single CAN message from `socket`. Applies filter, yields to block if it matches.
    #
    # @param socket [Socket] The CAN socket.
    # @param filter [Integer, Range, Array<Integer>, nil] Optional filter for CAN IDs.
    # @yield [message] Yields the message if it passes filtering.
    # @return [void]
    def process_message(socket, filter, can_fd, dbc, &block)
      message = @adapter.receive_message(socket: socket, can_fd: can_fd)
      return if message.nil?
      return if filter && !matches_filter?(message_id: message[:id], filter: filter)

      if dbc
        decoded = dbc.decode_can(message[:id], message[:data])
        message[:decoded] = decoded if decoded
      end

      block.call(message)
    rescue StandardError => e
      @logger.error("Unexpected error in listening loop: #{e.message}")
    end

    # Checks whether the given message ID matches the specified filter.
    #
    # @param message_id [Integer] The ID of the incoming CAN message.
    # @param filter [Integer, Range, Array<Integer>, nil]
    # @return [Boolean]
    def matches_filter?(message_id:, filter:)
      case filter
      when Integer then message_id == filter
      when Range   then filter.cover?(message_id)
      when Array   then filter.include?(message_id)
      else true
      end
    end
  end
end
