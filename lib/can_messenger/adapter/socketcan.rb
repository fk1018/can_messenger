# frozen_string_literal: true

require "socket"
require_relative "base"

module CanMessenger
  module Adapter
    # Adapter implementation for Linux SocketCAN interfaces.
    class Socketcan < Base
      FRAME_SIZE = 16
      CANFD_FRAME_SIZE = 72
      MIN_FRAME_SIZE = 8
      MAX_FD_DATA = 64
      TIMEOUT = [1, 0].pack("l_2")

      # Creates and configures a CAN socket bound to the interface.
      # rubocop:disable Metrics/MethodLength
      def open_socket(can_fd: false)
        Socket.open(Socket::PF_CAN, Socket::SOCK_RAW, Socket::CAN_RAW).tap do |socket|
          socket.bind(Socket.pack_sockaddr_can(interface_name))
          socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, TIMEOUT)
          if can_fd && Socket.const_defined?(:CAN_RAW_FD_FRAMES)
            socket.setsockopt(Socket.const_defined?(:SOL_CAN_RAW) ? Socket::SOL_CAN_RAW : Socket::CAN_RAW,
                              Socket::CAN_RAW_FD_FRAMES, 1)
          end
        end
      rescue StandardError => e
        logger.error("Error creating CAN socket on interface #{interface_name}: #{e}")
        nil
      end
      # rubocop:enable Metrics/MethodLength

      # Builds a raw CAN or CAN FD frame for SocketCAN.
      def build_can_frame(id:, data:, extended_id: false, can_fd: false) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/PerceivedComplexity
        if can_fd
          raise ArgumentError, "CAN FD data cannot exceed #{MAX_FD_DATA} bytes" if data.size > MAX_FD_DATA
        elsif data.size > 8
          raise ArgumentError, "CAN data cannot exceed 8 bytes"
        end

        # Mask the ID to 29 bits
        can_id = id & 0x1FFFFFFF
        # Set bit 31 for extended frames
        can_id |= 0x80000000 if extended_id

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
      def receive_message(socket:, can_fd: false)
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
        extended = raw_id.anybits?(0x80000000)
        id = raw_id & 0x1FFFFFFF

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
    end
  end
end
