# frozen_string_literal: true

require "socket"
require "io/wait"
require_relative "base"
require_relative "../constants"

module CanMessenger
  module Adapter
    # Sends and receives frames through Linux SocketCAN raw sockets.
    #
    # Supports classic CAN and CAN FD, with CAN ID byte order resolved by Base.
    # Frame building and parsing can also be used without opening an interface.
    #
    # @example Building a classic CAN frame
    #   adapter = CanMessenger::Adapter::Socketcan.new(interface_name: "can0", logger: Logger.new($stdout))
    #   frame = adapter.build_can_frame(id: 0x123, data: [0xDE, 0xAD])
    #   frame.bytesize # => 16
    class Socketcan < Base # rubocop:disable Metrics/ClassLength
      # Linux protocol and socket-option identifiers for raw CAN and CAN FD support.
      CAN_RAW = 1
      SOL_CAN_BASE = 100
      SOL_CAN_RAW = SOL_CAN_BASE + CAN_RAW
      CAN_RAW_FD_FRAMES = 5

      # Complete frame sizes include the header and the fixed-size payload area.
      FRAME_SIZE = 16
      CANFD_FRAME_SIZE = 72
      # Both frame layouts place payload bytes after an eight-byte header.
      MIN_FRAME_SIZE = 8
      MAX_FD_DATA = 64
      MAX_STANDARD_ID = 0x7FF

      # sockaddr_can has a native family, alignment padding, interface index, and address union.
      SOCKADDR_CAN_ADDR_SIZE = 16
      SOCKADDR_CAN_SIZE = 24
      SOCKADDR_CAN_PADDING = 2
      # Kernel receive timeout as a native timeval: seconds followed by microseconds.
      TIMEOUT = [1, 0].pack("l_2")
      # Raw CAN does not use the protocol-specific address union.
      ZERO_CAN_ADDR = "\x00" * SOCKADDR_CAN_ADDR_SIZE

      # Creates and configures a CAN socket bound to the interface.
      #
      # Socket creation or configuration errors are logged. Any partially opened
      # socket is closed before returning nil.
      #
      # @param [Boolean, nil] can_fd Whether to enable CAN FD reception and transmission
      # @return [Socket, nil] The bound socket, or nil if it could not be opened
      def open_socket(can_fd: nil)
        socket = Socket.open(Socket::PF_CAN, Socket::SOCK_RAW, CAN_RAW)
        configure_socket(socket, can_fd: can_fd)
        socket
      rescue StandardError => e
        close_socket(socket)
        logger.error("Error creating CAN socket on interface #{interface_name}: #{e}")
        nil
      end

      # Builds a raw CAN or CAN FD frame for SocketCAN.
      #
      # Sets the extended-frame flag when requested and zero-pads the payload area.
      # The header records the supplied byte count, excluding that padding.
      #
      # @param [Integer] id The CAN identifier without frame flags
      # @param [Array<Integer>] data Payload bytes in 0..255; at most 8 for classic CAN or 64 for CAN FD
      # @param [Boolean] extended_id Whether to use a 29-bit identifier instead of an 11-bit identifier
      # @param [Boolean, nil] can_fd Whether to build a CAN FD frame; nil selects classic CAN
      # @return [String] A 16-byte classic CAN frame or a 72-byte CAN FD frame
      # @raise [ArgumentError] If the identifier, payload type, byte values, or payload length are invalid
      def build_can_frame(id:, data:, extended_id: false, can_fd: nil) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/PerceivedComplexity
        validate_data!(data)

        if can_fd
          raise ArgumentError, "CAN FD data cannot exceed #{MAX_FD_DATA} bytes" if data.size > MAX_FD_DATA
        elsif data.size > 8
          raise ArgumentError, "CAN data cannot exceed 8 bytes"
        end

        validate_can_id!(id, extended_id: extended_id)

        can_id = id
        # Set bit 31 for extended frames
        can_id |= Constants::EXTENDED_ID_FLAG if extended_id

        # Pack the ID based on endianness
        id_bytes = endianness == :big ? [can_id].pack("L>") : [can_id].pack("V")

        dlc_and_pad = [data.size, 0, 0, 0].pack("C*")

        payload = if can_fd
                    data.pack("C*").ljust(MAX_FD_DATA, "\x00")
                  else
                    data.pack("C*").ljust(8, "\x00")
                  end

        id_bytes + dlc_and_pad + payload
      end

      # Reads a frame from the socket and parses it into a hash.
      #
      # Uses a one-second readiness timeout followed by a nonblocking receive so
      # an idle listener can stop. A timeout or loss of readiness returns nil;
      # other receive errors are logged and also return nil.
      #
      # @param [Socket] socket The bound CAN socket to read from
      # @param [Boolean, nil] can_fd Whether to reserve space for CAN FD; nil selects classic CAN
      # @return [Hash, nil] The parsed message, or nil when no frame can be returned
      def receive_message(socket:, can_fd: nil)
        return nil unless socket.wait_readable(1)

        frame_size = can_fd ? CANFD_FRAME_SIZE : FRAME_SIZE
        frame = socket.recv_nonblock(frame_size)
        return nil if frame.nil? || frame.size < MIN_FRAME_SIZE

        parse_frame(frame: frame, can_fd: can_fd)
      rescue IO::WaitReadable
        nil
      rescue StandardError => e
        logger.error("Error receiving CAN message on interface #{interface_name}: #{e}")
        nil
      end

      # Parses a raw CAN frame string into a hash with id, data and extended flag.
      #
      # The :id excludes frame flags. Remote requests also include :remote => true
      # and the requested byte count in :dlc, with empty :data. If the header is
      # present but the declared payload is incomplete, :data is empty.
      # Parsing errors are logged and return nil.
      #
      # @param [String] frame The raw frame bytes, including the header
      # @param [Boolean, nil] can_fd The frame format, or nil to infer it from the frame size
      # @return [Hash, nil] The message, or nil if the header is missing or parsing fails
      def parse_frame(frame:, can_fd: nil) # rubocop:disable Metrics/MethodLength
        return nil unless frame && frame.size >= MIN_FRAME_SIZE

        raw_id = unpack_frame_id(frame: frame)
        extended = raw_id.anybits?(Constants::EXTENDED_ID_FLAG)
        id = raw_id & Constants::MAX_EXTENDED_ID

        data_length = frame_data_length(frame, can_fd: can_fd)

        if raw_id.anybits?(Constants::REMOTE_TRANSMISSION_REQUEST_FLAG)
          return { id: id, data: [], extended: extended, remote: true, dlc: data_length }
        end

        data = if frame.size >= MIN_FRAME_SIZE + data_length
                 frame[MIN_FRAME_SIZE, data_length].unpack("C*")
               else
                 []
               end

        { id: id, data: data, extended: extended }
      rescue StandardError => e
        logger.error("Error parsing CAN frame: #{e}")
        nil
      end

      private

      # Reads the declared payload length using the selected frame layout.
      #
      # @param [String] frame A frame containing at least the complete header
      # @param [Boolean, nil] can_fd Whether to use CAN FD, or nil to infer the format from size
      # @return [Integer] The declared number of payload bytes
      def frame_data_length(frame, can_fd:)
        use_fd = can_fd.nil? ? frame.size >= CANFD_FRAME_SIZE : can_fd
        use_fd ? frame[4].ord : frame[4].ord & 0x0F
      end

      # Reads the CAN identifier and frame flags using the configured byte order.
      #
      # @param [String] frame The raw frame containing the four-byte identifier field
      # @return [Integer] The identifier with any frame flags still set
      def unpack_frame_id(frame:)
        if endianness == :big
          frame[0..3].unpack1("L>")
        else
          frame[0..3].unpack1("V")
        end
      end

      # Binds a socket, sets its kernel receive timeout, and optionally enables CAN FD.
      #
      # receive_message also bounds its readiness wait because the kernel timeout
      # alone does not limit Ruby's wait for a readable socket.
      #
      # @param [Socket] socket The newly opened CAN socket
      # @param [Boolean, nil] can_fd Whether to enable CAN FD frames
      # @return [void]
      # @raise [ArgumentError] If the configured interface cannot be resolved
      # @raise [SystemCallError] If binding or setting a socket option fails
      def configure_socket(socket, can_fd:)
        socket.bind(build_sockaddr_can(interface_index))
        socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, TIMEOUT)
        return unless can_fd

        socket.setsockopt(SOL_CAN_RAW, CAN_RAW_FD_FRAMES, 1)
      end

      # Closes a socket during failed setup without masking the original error.
      #
      # @param [Socket, nil] socket The socket to close, if one was created
      # @return [void]
      def close_socket(socket)
        return unless socket
        return if socket.respond_to?(:closed?) && socket.closed?

        socket.close
      rescue StandardError
        # Ignore close errors so we can report the original failure.
      end

      # Resolves the configured interface name to its Linux interface index.
      #
      # Uses Ruby's interface list first, then falls back to the sysfs entry.
      #
      # @return [Integer] The positive interface index used for binding
      # @raise [ArgumentError] If neither lookup can resolve the interface
      def interface_index
        index = interface_index_from_ifaddrs || interface_index_from_sysfs
        return index if index

        raise ArgumentError, "Unknown CAN interface #{interface_name}"
      end

      # Looks up the interface index through Ruby's network-interface enumeration.
      #
      # @return [Integer, nil] The index, or nil if unavailable, unsupported, or not found
      def interface_index_from_ifaddrs
        return nil unless Socket.respond_to?(:getifaddrs)

        Socket.getifaddrs.each do |ifaddr|
          next unless ifaddr.name == interface_name
          next unless ifaddr.ifindex&.positive?

          return ifaddr.ifindex
        end

        nil
      rescue NoMethodError, SystemCallError
        nil
      end

      # Reads the Linux sysfs interface index as a fallback for Ruby's interface lookup.
      #
      # @return [Integer, nil] The positive index, or nil if the entry is missing, unreadable, or invalid
      def interface_index_from_sysfs
        ifindex_path = File.join("/sys/class/net", interface_name, "ifindex")
        return nil unless File.file?(ifindex_path)

        index = Integer(File.read(ifindex_path).strip, 10)
        index.positive? ? index : nil
      rescue ArgumentError, SystemCallError
        nil
      end

      # Packs the native Linux sockaddr_can structure used to bind a raw socket.
      #
      # Socket addresses always use host byte order, independently of the byte
      # order selected for CAN identifiers in frame building and parsing.
      #
      # @param [Integer] ifindex The resolved Linux interface index
      # @return [String] The 24-byte packed socket address
      # @raise [RuntimeError] If the packed layout does not have the expected size
      def build_sockaddr_can(ifindex)
        can_family = Socket.const_defined?(:AF_CAN) ? Socket::AF_CAN : Socket::PF_CAN
        sockaddr = [can_family, ifindex, ZERO_CAN_ADDR].pack("S!x#{SOCKADDR_CAN_PADDING}i!a#{SOCKADDR_CAN_ADDR_SIZE}")
        return sockaddr if sockaddr.bytesize == SOCKADDR_CAN_SIZE

        raise "sockaddr_can must be #{SOCKADDR_CAN_SIZE} bytes, got #{sockaddr.bytesize}"
      end

      # Checks that an identifier fits the selected CAN frame format without flags.
      #
      # @param [Object] id The caller-supplied identifier to validate
      # @param [Boolean] extended_id Whether the allowed range is 29 bits instead of 11 bits
      # @return [void]
      # @raise [ArgumentError] If the identifier is not an integer or lies outside the allowed range
      def validate_can_id!(id, extended_id:)
        raise ArgumentError, "id must be an Integer" unless id.is_a?(Integer)
        raise ArgumentError, "CAN id cannot be negative" if id.negative?

        max_id = extended_id ? Constants::MAX_EXTENDED_ID : MAX_STANDARD_ID
        return if id <= max_id

        raise ArgumentError, "#{extended_id ? "Extended" : "Standard"} CAN id cannot exceed 0x#{max_id.to_s(16).upcase}"
      end

      # Checks the payload container and each byte before binary packing.
      #
      # Explicit validation prevents Array#pack from silently wrapping integers
      # outside the byte range or coercing noninteger values.
      #
      # @param [Object] data The caller-supplied payload to validate
      # @return [void]
      # @raise [ArgumentError] If the payload is not an array of integers in 0..255
      def validate_data!(data)
        raise ArgumentError, "data must be an Array of byte Integers" unless data.is_a?(Array)
        return if data.all? { |byte| byte.is_a?(Integer) && byte.between?(0, 255) }

        raise ArgumentError, "data bytes must be Integers between 0 and 255"
      end
    end
  end
end
