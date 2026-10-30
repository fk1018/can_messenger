# frozen_string_literal: true

module CanMessenger
  module Adapter
    # Defines the transport interface used by Messenger.
    #
    # Provides shared interface, logging, and CAN ID byte-order configuration.
    # Concrete adapters implement socket creation, frame building, receiving,
    # and parsing for their transport.
    #
    # @abstract Subclass and implement the four transport methods below.
    class Base
      attr_reader :interface_name, :logger, :endianness

      # Detects the host's byte order by comparing native and explicit integer packing.
      #
      # @return [Symbol] :little or :big
      def self.native_endianness
        native = pack_uint(1, "I")
        return :little if native == pack_uint(1, "V")
        return :big if native == pack_uint(1, "N")

        # Fallback for unusual platforms.
        native.bytes.first == 1 ? :little : :big
      end

      # Packs an unsigned integer for byte-order detection.
      #
      # @param [Integer] value The integer to pack
      # @param [String] template The Array#pack format specifying width and byte order
      # @return [String] The packed bytes
      def self.pack_uint(value, template)
        [value].pack(template)
      end
      private_class_method :pack_uint

      # Initializes the shared adapter configuration without opening a socket.
      #
      # Resolves :native to the host's byte order so transport methods only need
      # to handle :little and :big.
      #
      # @param [String] interface_name The CAN interface to use (e.g., "can0")
      # @param [Logger] logger The logger for transport errors and diagnostic messages
      # @param [Symbol, String] endianness CAN ID byte order: native, little, or big
      # @return [void]
      # @raise [ArgumentError] If the byte-order setting is unsupported
      def initialize(interface_name:, logger:, endianness: :native)
        @interface_name = interface_name
        @logger = logger
        normalized_endianness = normalize_endianness(endianness)
        @endianness = normalized_endianness == :native ? self.class.native_endianness : normalized_endianness
      end

      # Opens a socket for the underlying interface.
      #
      # Messenger owns the returned socket and closes it after sending or listening.
      #
      # @param [Boolean, nil] can_fd Whether to enable CAN FD frames
      # @return [Object, nil] The adapter-specific socket, or nil if opening fails
      # @raise [NotImplementedError] If a subclass does not implement this method
      def open_socket(can_fd: false)
        raise NotImplementedError, "open_socket must be implemented in subclasses"
      end

      # Builds a frame ready to be written to the socket.
      #
      # @param [Integer] id The CAN identifier without frame flags
      # @param [Array<Integer>] data The payload bytes, each in 0..255
      # @param [Boolean] extended_id Whether to use a 29-bit identifier instead of an 11-bit identifier
      # @param [Boolean, nil] can_fd Whether to build a CAN FD frame
      # @return [String] The serialized frame
      # @raise [NotImplementedError] If a subclass does not implement this method
      def build_can_frame(id:, data:, extended_id: false, can_fd: false)
        raise NotImplementedError, "build_can_frame must be implemented in subclasses"
      end

      # Receives and parses a frame from the socket.
      #
      # Implementations should bound their receive wait and return nil on timeout
      # so Messenger can check whether listening has been stopped.
      #
      # @param [Object] socket The adapter-specific socket to read from
      # @param [Boolean, nil] can_fd Whether CAN FD reception is enabled
      # @return [Hash, nil] A message with :id, :data, and :extended, or nil when no message is available
      # @raise [NotImplementedError] If a subclass does not implement this method
      def receive_message(socket:, can_fd: false)
        raise NotImplementedError, "receive_message must be implemented in subclasses"
      end

      # Parses a raw frame string into a message hash.
      #
      # Remote transmission requests should include :remote and :dlc, with empty
      # :data, so Messenger can distinguish them from frames containing signals.
      #
      # @param [String] frame The serialized frame
      # @param [Boolean, nil] can_fd Whether to parse CAN FD, or nil for adapter-specific detection
      # @return [Hash, nil] A message with :id, :data, and :extended, or nil if parsing fails
      # @raise [NotImplementedError] If a subclass does not implement this method
      def parse_frame(frame:, can_fd: false)
        raise NotImplementedError, "parse_frame must be implemented in subclasses"
      end

      private

      # Converts a supported byte-order setting to a symbol.
      #
      # String settings are case-insensitive and may contain surrounding whitespace.
      #
      # @param [Symbol, String] endianness The requested CAN ID byte order
      # @return [Symbol] :native, :little, or :big
      # @raise [ArgumentError] If the setting does not name a supported byte order
      def normalize_endianness(endianness)
        normalized = endianness.is_a?(String) ? endianness.strip.downcase.to_sym : endianness
        return normalized if %i[native little big].include?(normalized)

        raise ArgumentError, "endianness must be :native, :little, or :big"
      end
    end
  end
end
