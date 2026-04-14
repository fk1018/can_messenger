# frozen_string_literal: true

require "socket"
require_relative "base"
require_relative "../constants"

module CanMessenger
  module Adapter
    # Adapter implementation for Linux SocketCAN interfaces.
    class Socketcan < Base # rubocop:disable Metrics/ClassLength
      CAN_RAW = 1
      SOL_CAN_BASE = 100
      SOL_CAN_RAW = SOL_CAN_BASE + CAN_RAW
      CAN_RAW_FD_FRAMES = 5
      FRAME_SIZE = 16
      CANFD_FRAME_SIZE = 72
      MIN_FRAME_SIZE = 8
      MAX_FD_DATA = 64
      MAX_STANDARD_ID = 0x7FF
      SOCKADDR_CAN_ADDR_SIZE = 16
      SOCKADDR_CAN_SIZE = 24
      SOCKADDR_CAN_PADDING = 2
      TIMEOUT = [1, 0].pack("l_2")
      ZERO_CAN_ADDR = "\x00" * SOCKADDR_CAN_ADDR_SIZE

      # Creates and configures a CAN socket bound to the interface.
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
      def build_can_frame(id:, data:, extended_id: false, can_fd: nil) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/PerceivedComplexity
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
      def receive_message(socket:, can_fd: nil)
        frame_size = can_fd ? CANFD_FRAME_SIZE : FRAME_SIZE
        frame = socket.recv(frame_size)
        return nil if frame.nil? || frame.size < MIN_FRAME_SIZE

        parse_frame(frame: frame, can_fd: can_fd)
      rescue IO::WaitReadable
        nil
      rescue StandardError => e
        logger.error("Error receiving CAN message on interface #{interface_name}: #{e}")
        nil
      end

      # Parses a raw CAN frame string into a hash with id, data and extended flag.
      def parse_frame(frame:, can_fd: nil) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/PerceivedComplexity
        return nil unless frame && frame.size >= MIN_FRAME_SIZE

        use_fd = can_fd.nil? ? frame.size >= CANFD_FRAME_SIZE : can_fd

        raw_id = unpack_frame_id(frame: frame)
        extended = raw_id.anybits?(Constants::EXTENDED_ID_FLAG)
        id = raw_id & Constants::MAX_EXTENDED_ID

        data_length = if use_fd
                        frame[4].ord
                      else
                        frame[4].ord & 0x0F
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

      def unpack_frame_id(frame:)
        if endianness == :big
          frame[0..3].unpack1("L>")
        else
          frame[0..3].unpack1("V")
        end
      end

      def configure_socket(socket, can_fd:)
        socket.bind(build_sockaddr_can(interface_index))
        socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, TIMEOUT)
        return unless can_fd

        socket.setsockopt(SOL_CAN_RAW, CAN_RAW_FD_FRAMES, 1)
      end

      def close_socket(socket)
        return unless socket
        return if socket.respond_to?(:closed?) && socket.closed?

        socket.close
      rescue StandardError
        # Ignore close errors so we can report the original failure.
      end

      def interface_index
        index = interface_index_from_ifaddrs || interface_index_from_sysfs
        return index if index

        raise ArgumentError, "Unknown CAN interface #{interface_name}"
      end

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

      def interface_index_from_sysfs
        ifindex_path = File.join("/sys/class/net", interface_name, "ifindex")
        return nil unless File.file?(ifindex_path)

        index = Integer(File.read(ifindex_path).strip, 10)
        index.positive? ? index : nil
      rescue ArgumentError, SystemCallError
        nil
      end

      def build_sockaddr_can(ifindex)
        can_family = Socket.const_defined?(:AF_CAN) ? Socket::AF_CAN : Socket::PF_CAN
        sockaddr = [can_family, ifindex, ZERO_CAN_ADDR].pack("S!x#{SOCKADDR_CAN_PADDING}i!a#{SOCKADDR_CAN_ADDR_SIZE}")
        return sockaddr if sockaddr.bytesize == SOCKADDR_CAN_SIZE

        raise "sockaddr_can must be #{SOCKADDR_CAN_SIZE} bytes, got #{sockaddr.bytesize}"
      end

      def validate_can_id!(id, extended_id:)
        raise ArgumentError, "id must be an Integer" unless id.is_a?(Integer)
        raise ArgumentError, "CAN id cannot be negative" if id.negative?

        max_id = extended_id ? Constants::MAX_EXTENDED_ID : MAX_STANDARD_ID
        return if id <= max_id

        raise ArgumentError, "#{extended_id ? "Extended" : "Standard"} CAN id cannot exceed 0x#{max_id.to_s(16).upcase}"
      end
    end
  end
end
