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
  class Messenger # rubocop:disable Metrics/ClassLength
    FRAME_SIZE = 16
    MIN_FRAME_SIZE = 8
    TIMEOUT = [1, 0].pack("l_2")

    # Initializes a new Messenger instance.
    #
    # @param [String] interface_name The CAN interface to use (e.g., 'can0').
    # @param [Logger, nil] logger Optional logger for error handling and debug information.
    # @param [Symbol] endianness The endianness of the CAN ID (default: :big) can be :big or :little.
    # @return [void]
    def initialize(interface_name:, logger: nil, endianness: :big)
      @interface_name = interface_name
      @logger = logger || Logger.new($stdout)
      @listening = true # Control flag for listening loop
      @endianness    = endianness # :big or :little
    end

    # Sends a CAN message by writing directly to a raw CAN socket
    #
    # @param [Integer] id The CAN ID of the message (up to 29 bits for extended IDs).
    # @param [Array<Integer>] data The data bytes of the CAN message (0 to 8 bytes).
    # @return [void]
    def send_can_message(id:, data:, extended_id: false)
      with_socket do |socket|
        frame = build_can_frame(id: id, data: data, extended_id: extended_id)
        socket.write(frame)
      end
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
        @logger.info("Started listening on #{@interface_name}")
        process_message(socket, filter, &block) while @listening
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
    def with_socket
      socket = open_can_socket
      return @logger.error("Failed to open socket, cannot continue operation.") if socket.nil?

      yield socket
    ensure
      socket&.close
    end

    # Creates and configures a CAN socket bound to @interface_name.
    #
    # @return [Socket, nil] The configured CAN socket, or nil if the socket cannot be opened.
    def open_can_socket
      socket = Socket.open(Socket::PF_CAN, Socket::SOCK_RAW, Socket::CAN_RAW)
      socket.bind(Socket.pack_sockaddr_can(@interface_name))
      socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, TIMEOUT)
      socket
    rescue StandardError => e
      @logger.error("Error creating CAN socket on interface #{@interface_name}: #{e}")
      nil
    end

    # Builds a raw CAN frame for SocketCAN, big-endian ID, 1-byte DLC, up to 8 data bytes, and 3 padding bytes.
    #
    # @param id [Integer] the CAN ID
    # @param data [Array<Integer>] up to 8 bytes
    # @return [String] a 16-byte string representing a classic CAN frame
    def build_can_frame(id:, data:, extended_id: false)
      raise ArgumentError, "CAN data cannot exceed 8 bytes" if data.size > 8

      # Mask the ID to 29 bits
      can_id = id & 0x1FFFFFFF

      # If extended_id == true, set bit 31 (CAN_EFF_FLAG)
      can_id |= 0x80000000 if extended_id

      # Pack the 4‐byte ID (big-endian or little-endian)
      id_bytes = @endianness == :big ? [can_id].pack("L>") : [can_id].pack("V")

      # 1 byte for DLC, then 3 bytes of padding
      dlc_and_pad = [data.size, 0, 0, 0].pack("C*")

      # Up to 8 data bytes, pad with 0 if fewer
      payload = data.pack("C*").ljust(8, "\x00")

      # Total 16 bytes (4 for ID, 1 for DLC, 3 padding, 8 data)
      id_bytes + dlc_and_pad + payload
    end

    # Processes a single CAN message from `socket`. Applies filter, yields to block if it matches.
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

    # Reads a frame from the socket and parses it into { id:, data: }, or nil if none is received.
    #
    # @param socket [Socket]
    # @return [Hash, nil]
    def receive_message(socket:)
      frame = socket.recv(FRAME_SIZE)
      return nil if frame.nil? || frame.size < MIN_FRAME_SIZE

      parse_frame(frame: frame)
    rescue IO::WaitReadable
      nil
    rescue StandardError => e
      @logger.error("Error receiving CAN message on interface #{@interface_name}: #{e}")
      nil
    end

    # Parses a raw CAN frame into { id: Integer, data: Array<Integer> }, or nil on error.
    #
    # @param [String] frame
    # @return [Hash, nil]
    def parse_frame(frame:) # rubocop:disable Metrics/MethodLength
      return nil unless frame && frame.size >= MIN_FRAME_SIZE

      raw_id = unpack_frame_id(frame: frame)

      # Determine if EFF bit is set
      extended = raw_id.anybits?(0x80000000)
      # or raw_id.anybits?(0x80000000) if your Ruby version supports `Integer#anybits?`

      # Now mask off everything except the lower 29 bits
      id = raw_id & 0x1FFFFFFF

      # DLC is the lower 4 bits of byte 4
      data_length = frame[4].ord & 0x0F

      # Extract data
      data = if frame.size >= MIN_FRAME_SIZE + data_length
               frame[MIN_FRAME_SIZE, data_length].unpack("C*")
             else
               []
             end

      { id: id, data: data, extended: extended }
    rescue StandardError => e
      @logger.error("Error parsing CAN frame: #{e}")
      nil
    end

    def unpack_frame_id(frame:)
      if @endianness == :big
        frame[0..3].unpack1("L>")
      else
        frame[0..3].unpack1("V")
      end
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
