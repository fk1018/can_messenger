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
    CANFD_FRAME_SIZE = 72
    MIN_FRAME_SIZE = 8
    MAX_FD_DATA = 64
    TIMEOUT = [1, 0].pack("l_2")

    # Initializes a new Messenger instance.
    #
    # @param [String] interface_name The CAN interface to use (e.g., 'can0').
    # @param [Logger, nil] logger Optional logger for error handling and debug information.
    # @param [Symbol] endianness The endianness of the CAN ID (default: :big) can be :big or :little.
    # @return [void]
    def initialize(interface_name:, logger: nil, endianness: :big, can_fd: false)
      @interface_name = interface_name
      @logger = logger || Logger.new($stdout)
      @listening = true # Control flag for listening loop
      @endianness    = endianness # :big or :little
      @can_fd        = can_fd
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
        frame = build_can_frame(id: id, data: data, extended_id: extended_id, can_fd: use_fd)
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
      socket = open_can_socket(can_fd: can_fd)
      return @logger.error("Failed to open socket, cannot continue operation.") if socket.nil?

      yield socket
    ensure
      socket&.close
    end

    # Creates and configures a CAN socket bound to @interface_name.
    #
    # @return [Socket, nil] The configured CAN socket, or nil if the socket cannot be opened.
    def open_can_socket(can_fd: @can_fd) # rubocop:disable Metrics/MethodLength
      socket = Socket.open(Socket::PF_CAN, Socket::SOCK_RAW, Socket::CAN_RAW)
      socket.bind(Socket.pack_sockaddr_can(@interface_name))
      socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, TIMEOUT)
      if can_fd && Socket.const_defined?(:CAN_RAW_FD_FRAMES)
        socket.setsockopt(Socket.const_defined?(:SOL_CAN_RAW) ? Socket::SOL_CAN_RAW : Socket::CAN_RAW,
                          Socket::CAN_RAW_FD_FRAMES, 1)
      end
      socket
    rescue StandardError => e
      @logger.error("Error creating CAN socket on interface #{@interface_name}: #{e}")
      nil
    end

    # Builds a raw CAN or CAN FD frame for SocketCAN.
    #
    # @param id [Integer] the CAN ID
    # @param data [Array<Integer>] data bytes (up to 8 for classic, 64 for CAN FD)
    # @param can_fd [Boolean] whether to build a CAN FD frame
    # @return [String] the packed CAN frame
    def build_can_frame(id:, data:, extended_id: false, can_fd: false) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/PerceivedComplexity
      if can_fd
        raise ArgumentError, "CAN FD data cannot exceed #{MAX_FD_DATA} bytes" if data.size > MAX_FD_DATA
      elsif data.size > 8
        raise ArgumentError, "CAN data cannot exceed 8 bytes"
      end

      # Mask the ID to 29 bits
      can_id = id & 0x1FFFFFFF

      # If extended_id == true, set bit 31 (CAN_EFF_FLAG)
      can_id |= 0x80000000 if extended_id

      # Pack the 4‐byte ID (big-endian or little-endian)
      id_bytes = @endianness == :big ? [can_id].pack("L>") : [can_id].pack("V")

      # 1 byte for DLC/length, then 3 bytes for flags/reserved
      dlc_and_pad = [data.size, 0, 0, 0].pack("C*")

      payload = if can_fd
                  data.pack("C*").ljust(MAX_FD_DATA, "\x00")
                else
                  data.pack("C*").ljust(8, "\x00")
                end

      id_bytes + dlc_and_pad + payload
    end

    # Processes a single CAN message from `socket`. Applies filter, yields to block if it matches.
    #
    # @param socket [Socket] The CAN socket.
    # @param filter [Integer, Range, Array<Integer>, nil] Optional filter for CAN IDs.
    # @yield [message] Yields the message if it passes filtering.
    # @return [void]
    def process_message(socket, filter, can_fd, dbc, &block)
      message = receive_message(socket: socket, can_fd: can_fd)
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

    # Reads a frame from the socket and parses it into { id:, data: }, or nil if none is received.
    #
    # @param socket [Socket]
    # @return [Hash, nil]
    def receive_message(socket:, can_fd: false)
      frame_size = can_fd ? CANFD_FRAME_SIZE : FRAME_SIZE
      frame = socket.recv(frame_size)
      return nil if frame.nil? || frame.size < MIN_FRAME_SIZE

      parse_frame(frame: frame, can_fd: can_fd)
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
    def parse_frame(frame:, can_fd: nil) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/PerceivedComplexity
      return nil unless frame && frame.size >= MIN_FRAME_SIZE

      use_fd = can_fd.nil? ? frame.size >= CANFD_FRAME_SIZE : can_fd

      raw_id = unpack_frame_id(frame: frame)

      # Determine if EFF bit is set
      extended = raw_id.anybits?(0x80000000)
      # or raw_id.anybits?(0x80000000) if your Ruby version supports `Integer#anybits?`

      # Now mask off everything except the lower 29 bits
      id = raw_id & 0x1FFFFFFF

      data_length = if use_fd
                      frame[4].ord
                    else
                      frame[4].ord & 0x0F
                    end

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
