# lib/can_messenger/messenger.rb
# frozen_string_literal: true

require "socket"
require "logger"

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
    FRAME_SIZE = 16
    MIN_FRAME_SIZE = 8
    TIMEOUT = [1, 0].pack("l_2")
    # Initializes a new Messenger instance.
    #
    # @param [String] interface_name The CAN interface to use (e.g., 'can0').
    # @param [Logger, nil] logger Optional logger for error handling and debug information.
    # @return [void]
    def initialize(interface_name:, logger: nil)
      @can_interface = interface_name
      @logger = logger || Logger.new($stdout)
      @listening = true # Control flag for listening loop
    end

    # Sends a CAN message using the `cansend` command.
    #
    # @param [Integer] id The CAN ID of the message.
    # @param [Array<Integer>] data The data bytes of the CAN message.
    # @return [void]
    def send_can_message(id:, data:)
      hex_id = format("%03X", id)
      hex_data = data.map { |byte| format("%02X", byte) }.join
      command = "cansend #{@can_interface} #{hex_id}##{hex_data}"
      system(command) # @todo validate command status
    rescue StandardError => e
      @logger.error("Error sending CAN message (ID: #{id}): #{e}")
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
    def start_listening(filter: nil, &block)
      return @logger.error("No block provided to handle messages.") unless block_given?

      with_socket do |socket|
        @logger.info("Started listening on #{@can_interface}")
        process_message(socket, filter, &block) while @listening
      end
    end

    # Stops the listening loop by setting @listening to false.
    #
    # This method can be called from an external thread or signal handler.
    # @return [void]
    def stop_listening
      @listening = false
      @logger.info("Stopped listening on #{@can_interface}")
    end

    private

    # Yields an open CAN socket to the given block.
    #
    # Opens a socket and, if successful, yields it to the block.
    # If the socket cannot be opened, logs an error and returns.
    #
    # @yield [socket] An open CAN socket.
    # @return [void]
    def with_socket
      socket = open_can_socket
      return @logger.error("Failed to open socket, cannot continue listening.") if socket.nil?

      yield socket
    ensure
      socket&.close
    end

    # Processes a single CAN message.
    #
    # Reads a message from the socket, applies the filter, and yields the message if appropriate.
    # If an error occurs during processing, it logs the error.
    #
    # @param socket [Socket] The CAN socket.
    # @param filter [Integer, Range, Array<Integer>, nil] Optional filter for CAN IDs.
    # @yield [message] Yields the message if it passes filtering.
    # @return [void]
    def process_message(socket, filter)
      message = receive_message(socket: socket)
      return if message.nil?
      return if filter && !matches_filter?(message_id: message[:id], filter: filter)

      yield(message)
    rescue StandardError => e
      @logger.error("Unexpected error in listening loop: #{e.message}")
    end

    # Creates and configures a CAN socket.
    #
    # @return [Socket, nil] The configured CAN socket, or nil if the socket cannot be opened.
    def open_can_socket
      socket = Socket.open(Socket::PF_CAN, Socket::SOCK_RAW, Socket::CAN_RAW)
      socket.bind(Socket.pack_sockaddr_can(@can_interface))
      socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, TIMEOUT)
      socket
    rescue StandardError => e
      @logger.error("Error creating CAN socket on interface #{@can_interface}: #{e}")
      nil
    end

    # Receives a CAN message from the given socket and parses it.
    #
    # This method attempts to read a frame from the provided CAN socket. It returns a parsed
    # message hash in the format `{ id: Integer, data: Array<Integer> }` if a valid frame is received.
    # If no frame is received, or if an error occurs, the method returns `nil`.
    #
    # @param socket [Socket] The CAN socket to read from.
    # @return [{ id: Integer, data: Array<Integer> }, nil] A hash representing the CAN message, or `nil` if no message
    #   is received or an error occurs.
    def receive_message(socket:)
      frame = socket.recv(FRAME_SIZE)
      return nil if frame.nil? || frame.size < MIN_FRAME_SIZE

      parse_frame(frame: frame)
    rescue IO::WaitReadable
      nil
    rescue StandardError => e
      @logger.error("Error receiving CAN message on interface #{@can_interface}: #{e}")
      nil
    end

    # Parses a raw CAN frame into a message hash.
    #
    # @param [String] frame The raw CAN frame.
    # @return [{ id: Integer, data: Array<Integer> }, nil] Parsed message with :id and :data keys,
    #   or nil if the frame is incomplete or an error occurs.
    def parse_frame(frame:)
      return nil unless frame && frame.size >= MIN_FRAME_SIZE

      id = frame[0..3].unpack1("L>") & 0x1FFFFFFF
      data_length = frame[4].ord & 0x0F
      data = (frame[MIN_FRAME_SIZE, data_length].unpack("C*") if frame.size >= MIN_FRAME_SIZE + data_length)
      { id: id, data: data }
    rescue StandardError => e
      @logger.error("Error parsing CAN frame: #{e}")
      nil
    end

    # Checks whether the given message ID matches the specified filter.
    #
    # The filter can be one of the following:
    # - An Integer, which requires an exact match.
    # - A Range of Integers, where the message ID must fall within the range.
    # - An Array of Integers, where the message ID must be included in the array.
    #
    # If the filter is nil or unrecognized, the method returns true.
    #
    # @param message_id [Integer] The ID of the incoming CAN message.
    # @param filter [Integer, Range, Array<Integer>, nil] The filter to apply.
    # @return [Boolean] Returns true if the message ID matches the filter otherwise false.
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
