# frozen_string_literal: true

module CanMessenger
  module Adapter
    # Base adapter defines the interface for CAN bus adapters.
    # Concrete adapters must implement all of the methods defined here.
    class Base
      attr_reader :interface_name, :logger, :endianness

      def self.native_endianness
        native = pack_uint(1, "I")
        return :little if native == pack_uint(1, "V")
        return :big if native == pack_uint(1, "N")

        # Fallback for unusual platforms.
        native.bytes.first == 1 ? :little : :big
      end

      def self.pack_uint(value, template)
        [value].pack(template)
      end
      private_class_method :pack_uint

      def initialize(interface_name:, logger:, endianness: :native)
        @interface_name = interface_name
        @logger = logger
        normalized_endianness = normalize_endianness(endianness)
        @endianness = normalized_endianness == :native ? self.class.native_endianness : normalized_endianness
      end

      # Open a socket for the underlying interface.
      # @return [Object] adapter-specific socket
      def open_socket(can_fd: false)
        raise NotImplementedError, "open_socket must be implemented in subclasses"
      end

      # Build a frame ready to be written to the socket.
      def build_can_frame(id:, data:, extended_id: false, can_fd: false)
        raise NotImplementedError, "build_can_frame must be implemented in subclasses"
      end

      # Receive and parse a frame from the socket.
      def receive_message(socket:, can_fd: false)
        raise NotImplementedError, "receive_message must be implemented in subclasses"
      end

      # Parse a raw frame string into a message hash.
      def parse_frame(frame:, can_fd: false)
        raise NotImplementedError, "parse_frame must be implemented in subclasses"
      end

      private

      def normalize_endianness(endianness)
        normalized = endianness.is_a?(String) ? endianness.strip.downcase.to_sym : endianness
        return normalized if %i[native little big].include?(normalized)

        raise ArgumentError, "endianness must be :native, :little, or :big"
      end
    end
  end
end
