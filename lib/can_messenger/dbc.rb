# frozen_string_literal: true

module CanMessenger
  # DBC (Database CAN) Parser and Encoder/Decoder
  #
  # This class provides functionality to parse DBC files and encode/decode CAN messages
  # according to the signal definitions. DBC files are a standard way to describe
  # CAN network communication.
  #
  # @example Loading and using a DBC file
  #   dbc = CanMessenger::DBC.load('vehicle.dbc')
  #
  #   # Encode a message with signal values
  #   frame = dbc.encode_can('EngineData', RPM: 2500, Temperature: 85.5)
  #   # => { id: 0x123, data: [0x09, 0xC4, 0xAB, 0x00, 0x00, 0x00, 0x00, 0x00] }
  #
  #   # Decode a received CAN frame
  #   decoded = dbc.decode_can(0x123, [0x09, 0xC4, 0xAB, 0x00, 0x00, 0x00, 0x00, 0x00])
  #   # => { name: 'EngineData', signals: { RPM: 2500.0, Temperature: 85.5 } }
  class DBC
    attr_reader :messages

    # Loads a DBC file from disk and parses its contents.
    #
    # @param [String] path The filesystem path to the DBC file
    # @return [DBC] A new DBC instance with parsed message definitions
    # @raise [Errno::ENOENT] If the file doesn't exist
    # @raise [ArgumentError] If the file contains invalid DBC syntax
    def self.load(path)
      new(File.read(path))
    end

    # Initializes a new DBC instance.
    #
    # @param [String] content The DBC file content to parse (optional)
    def initialize(content = "")
      @messages = {}
      parse(content) unless content.empty?
    end

    # Parses DBC content and populates the messages hash.
    #
    # This method processes each line of the DBC content, identifying message
    # definitions (BO_) and signal definitions (SG_). It builds a complete
    # message structure with all associated signals.
    #
    # @param [String] content The DBC file content to parse
    # @return [void]
    def parse(content) # rubocop:disable Metrics/MethodLength
      current = nil
      content.each_line do |line|
        line.strip!
        next if line.empty? || line.start_with?("BO_TX_BU_")

        if (msg = parse_message_line(line))
          current = msg
          @messages[msg.name] = msg
        elsif current && (sig = parse_signal_line(line, current))
          current.signals << sig
        end
      end
    end

    # Parses a message definition line from DBC content.
    #
    # Message lines follow the format: BO_ <ID> <Name>: <DLC> <Node>
    #
    # @param [String] line A single line from the DBC file
    # @return [Message, nil] A Message object if the line matches, nil otherwise
    def parse_message_line(line)
      return unless (m = line.match(/^BO_\s+(\d+)\s+(\w+)\s*:\s*(\d+)/))

      id = m[1].to_i
      name = m[2]
      dlc = m[3].to_i
      Message.new(id, name, dlc)
    end

    # Parses a signal definition line from DBC content.
    #
    # Signal lines follow the format:
    # SG_ <SignalName> : <StartBit>|<Length>@<Endianness><Sign> (<Factor>,<Offset>) [<Min>|<Max>] "<Unit>" <Receivers>
    #
    # @param [String] line A single line from the DBC file
    # @param [Message] _current The current message being processed (unused but kept for API consistency)
    # @return [Signal, nil] A Signal object if the line matches, nil otherwise
    def parse_signal_line(line, _current) # rubocop:disable Metrics/MethodLength
      return unless (m = line.match(/^SG_\s+(\w+)\s*:\s*(\d+)\|(\d+)@(\d)([+-])\s*\(([^,]+),([^\)]+)\)/))

      sig_name = m[1]
      start_bit = m[2].to_i
      length = m[3].to_i
      endian = m[4] == "1" ? :little : :big
      sign = m[5] == "-" ? :signed : :unsigned
      factor = m[6].to_f
      offset = m[7].to_f

      Signal.new(
        sig_name,
        start_bit: start_bit,
        length: length,
        endianness: endian,
        sign: sign,
        factor: factor,
        offset: offset
      )
    end # rubocop:enable Metrics/MethodLength

    # Encodes signal values into a CAN message frame.
    #
    # Takes a message name and a hash of signal values, then encodes them
    # into the appropriate byte array according to the DBC signal definitions.
    #
    # @param [String] name The name of the message to encode
    # @param [Hash<Symbol|String, Numeric>] values Signal names mapped to their values
    # @return [Hash] A hash containing :id (Integer) and :data (Array<Integer>)
    # @raise [ArgumentError] If the message name is not found in the DBC
    #
    # @example
    #   frame = dbc.encode_can('EngineData', RPM: 2500, Temperature: 85.5)
    #   # => { id: 0x123, data: [0x09, 0xC4, 0xAB, 0x00, 0x00, 0x00, 0x00, 0x00] }
    def encode_can(name, values)
      msg = @messages[name]
      raise ArgumentError, "Unknown message #{name}" unless msg

      { id: msg.id, data: msg.encode(values) }
    end

    # Decodes a CAN message frame into signal values.
    #
    # Takes a CAN ID and data bytes, finds the matching message definition,
    # and decodes the data into individual signal values according to the DBC.
    #
    # @param [Integer] id The CAN message ID
    # @param [Array<Integer>] data The CAN message data bytes
    # @return [Hash, nil] A hash containing :name (String) and :signals (Hash), or nil if no matching message
    #
    # @example
    #   decoded = dbc.decode_can(0x123, [0x09, 0xC4, 0xAB, 0x00, 0x00, 0x00, 0x00, 0x00])
    #   # => { name: 'EngineData', signals: { RPM: 2500.0, Temperature: 85.5 } }
    def decode_can(id, data)
      msg = @messages.values.find { |m| m.id == id }
      return nil unless msg

      { name: msg.name, signals: msg.decode(data) }
    end
  end

  # Represents a CAN message definition from a DBC file.
  #
  # A Message contains the basic message properties (ID, name, data length)
  # and a collection of Signal objects that define how data is structured
  # within the message payload.
  #
  # @example
  #   message = Message.new(0x123, 'EngineData', 8)
  #   message.signals << Signal.new('RPM', start_bit: 0, length: 16, ...)
  class Message
    attr_reader :id, :name, :dlc, :signals

    # Initializes a new Message instance.
    #
    # @param [Integer] id The CAN message ID (11-bit standard or 29-bit extended)
    # @param [String] name The symbolic name of the message
    # @param [Integer] dlc Data Length Code - number of bytes in the message (0-8 for classic CAN)
    def initialize(id, name, dlc)
      @id = id
      @name = name
      @dlc = dlc
      @signals = []
    end

    # Encodes signal values into the message byte array.
    #
    # Iterates through all signals in the message and encodes their values
    # into the appropriate bit positions within the message data bytes.
    #
    # @param [Hash<Symbol|String, Numeric>] values Signal names mapped to their values
    # @return [Array<Integer>] Array of bytes representing the encoded message
    def encode(values)
      bytes = Array.new(@dlc, 0)
      @signals.each do |sig|
        next unless values.key?(sig.name.to_sym) || values.key?(sig.name.to_s)

        v = values[sig.name.to_sym] || values[sig.name.to_s]
        sig.encode(bytes, v)
      end
      bytes
    end

    # Decodes message data bytes into individual signal values.
    #
    # Extracts and decodes each signal from the message data bytes,
    # applying the appropriate scaling (factor/offset) to produce
    # the final engineering unit values.
    #
    # @param [Array<Integer>] data The message data bytes to decode
    # @return [Hash<Symbol, Float>] Signal names mapped to their decoded values
    def decode(data)
      res = {}
      @signals.each do |sig|
        res[sig.name.to_sym] = sig.decode(data)
      end
      res
    end
  end

  # Represents a signal within a CAN message.
  #
  # A Signal defines how a piece of data is encoded within a CAN message,
  # including its bit position, length, byte order, signedness, and scaling.
  # Signals can represent physical values (like temperature, speed) that are
  # encoded as integers in the CAN frame but scaled to engineering units.
  #
  # @example Creating a signal for engine RPM
  #   rpm_signal = Signal.new('RPM',
  #     start_bit: 0,      # Starting at bit 0
  #     length: 16,        # 16 bits long
  #     endianness: :little, # Little-endian byte order
  #     sign: :unsigned,   # Unsigned integer
  #     factor: 0.25,      # Scale by 0.25
  #     offset: 0          # No offset
  #   )
  class Signal # rubocop:disable Metrics/ClassLength
    attr_reader :name, :start_bit, :length, :endianness, :sign, :factor, :offset

    # Initializes a new Signal instance.
    #
    # @param [String] name The signal name
    # @param [Integer] start_bit The starting bit position within the message (0-based)
    # @param [Integer] length The number of bits the signal occupies (1-64)
    # @param [Symbol] endianness Byte order - :little for little-endian, :big for big-endian
    # @param [Symbol] sign Value type - :unsigned for unsigned integers, :signed for signed integers
    # @param [Float] factor Scaling factor to convert raw value to engineering units
    # @param [Float] offset Offset to add after scaling
    def initialize(name, start_bit:, length:, endianness:, sign:, factor:, offset:) # rubocop:disable Metrics/ParameterLists
      @name = name
      @start_bit = start_bit
      @length = length
      @endianness = endianness
      @sign = sign
      @factor = factor
      @offset = offset
    end

    # Encodes a value into the message byte array at this signal's bit position.
    #
    # Converts the engineering unit value to a raw integer using the signal's
    # factor and offset, then places the bits into the appropriate positions
    # within the message bytes.
    #
    # @param [Array<Integer>] bytes The message byte array to modify
    # @param [Numeric] value The engineering unit value to encode
    # @return [void]
    # @raise [ArgumentError] If the value is out of range or signal exceeds message bounds
    def encode(bytes, value)
      raw = ((value - offset) / factor).round
      validate_signal_bounds(bytes.size)
      insert_bits(bytes, raw)
    end

    # Decodes this signal's value from the message byte array.
    #
    # Extracts the raw integer value from the appropriate bit positions,
    # then applies the signal's scaling (factor and offset) to convert
    # it to engineering units.
    #
    # @param [Array<Integer>] bytes The message byte array to decode from
    # @return [Float] The decoded value in engineering units
    def decode(bytes)
      raw = extract_bits(bytes)
      (raw * factor) + offset
    end

    private

    # Validates that the signal fits within the message boundaries.
    #
    # Ensures that all bits used by this signal fall within the message's
    # data length code (DLC) boundaries.
    #
    # @param [Integer] message_size_bytes The size of the message in bytes
    # @return [void]
    # @raise [ArgumentError] If signal bits exceed message boundaries or start_bit is negative
    def validate_signal_bounds(message_size_bytes)
      max_bit = start_bit + length - 1
      max_allowed_bit = (message_size_bytes * 8) - 1

      raise ArgumentError, "Signal #{name}: start_bit (#{start_bit}) cannot be negative" if start_bit.negative?

      return unless max_bit > max_allowed_bit

      raise ArgumentError,
            "Signal #{name}: signal bits #{start_bit}..#{max_bit} exceed message size " \
            "(#{message_size_bytes} bytes = #{max_allowed_bit + 1} bits)"
    end

    # Encodes a raw integer value into the message byte array.
    #
    # This is the main encoding method that coordinates validation,
    # value processing, and bit manipulation.
    #
    # @param [Array<Integer>] bytes The message byte array to modify
    # @param [Integer] raw The raw integer value to encode
    # @return [void]
    def insert_bits(bytes, raw)
      validate_raw_value(raw)
      processed_raw = process_raw_value(raw)
      write_bits_to_bytes(bytes, processed_raw)
    end

    # Validates the raw integer value before encoding.
    #
    # Performs range checking for both signed and unsigned values
    # to ensure they fit within the signal's bit length.
    #
    # @param [Integer] raw The raw value to validate
    # @return [void]
    # @raise [ArgumentError] If the value is out of range for the signal type
    def validate_raw_value(raw)
      validate_unsigned_value(raw)
      validate_signed_value(raw)
    end

    # Validates unsigned values to ensure they're not negative.
    #
    # @param [Integer] raw The raw value to validate
    # @return [void]
    # @raise [ArgumentError] If an unsigned value is negative
    def validate_unsigned_value(raw)
      return unless sign == :unsigned && raw.negative?

      raise ArgumentError, "Unsigned value cannot be negative: #{raw}"
    end

    # Validates signed values to ensure they fit in the signal's bit range.
    #
    # For signed signals, checks that the value fits within the two's complement
    # range defined by the signal's bit length.
    #
    # @param [Integer] raw The raw value to validate
    # @return [void]
    # @raise [ArgumentError] If a signed value exceeds the bit field's range
    def validate_signed_value(raw)
      return unless sign == :signed

      min_val = -(1 << (length - 1))
      max_val = (1 << (length - 1)) - 1
      return if raw.between?(min_val, max_val)

      raise ArgumentError,
            "Signed value #{raw} out of range [#{min_val}..#{max_val}] for #{length}-bit field"
    end

    # Processes the raw value for encoding (handles two's complement conversion).
    #
    # For signed negative values, converts them to two's complement representation.
    # Ensures the final value fits within the signal's bit length.
    #
    # @param [Integer] raw The raw value to process
    # @return [Integer] The processed value ready for bit manipulation
    def process_raw_value(raw)
      # Handle signed values: convert negative to two's complement
      raw = (1 << length) + raw if sign == :signed && raw.negative?
      # Ensure the value fits in the specified bit length
      raw & ((1 << length) - 1)
    end

    # Writes the processed bits into the message byte array.
    #
    # Iterates through each bit of the signal and places it in the correct
    # position within the message bytes, respecting the signal's endianness.
    #
    # @param [Array<Integer>] bytes The message byte array to modify
    # @param [Integer] raw The processed value to write
    # @return [void]
    def write_bits_to_bytes(bytes, raw)
      length.times do |i|
        bit = (raw >> i) & 1
        bit_pos = calculate_bit_position(i)
        byte_index, bit_index = calculate_byte_and_bit_indices(bit_pos)

        validate_bit_position(bit_pos, bytes.size)
        update_byte_with_bit(bytes, byte_index, bit_index, bit)
      end
    end

    # Calculates the bit position for a given bit offset within the signal.
    #
    # Handles both little-endian and big-endian bit ordering according
    # to the signal's endianness setting.
    #
    # @param [Integer] bit_offset The offset within the signal (0 to length-1)
    # @return [Integer] The absolute bit position within the message
    def calculate_bit_position(bit_offset)
      if endianness == :little
        start_bit + bit_offset
      else
        # For big-endian signals, the bit numbering within a byte follows MSB-first
        # ordering. This means that the most significant bit (MSB) is numbered 7,
        # and the least significant bit (LSB) is numbered 0. To calculate the absolute
        # bit position, we first determine the position of the MSB in the starting byte.
        #
        # The formula ((start_bit / 8) * 8) calculates the starting byte's base bit
        # position (aligned to the nearest multiple of 8). Adding (7 - (start_bit % 8))
        # adjusts this base position to point to the MSB of the starting byte.
        #
        # Finally, we subtract the bit offset to account for the signal's length and
        # position within the message.
        base = ((start_bit / 8) * 8) + (7 - (start_bit % 8))
        base - bit_offset
      end
    end

    # Calculates byte and bit indices from an absolute bit position.
    #
    # @param [Integer] bit_pos The absolute bit position within the message
    # @return [Array<Integer>] A two-element array [byte_index, bit_index]
    def calculate_byte_and_bit_indices(bit_pos)
      [bit_pos / 8, bit_pos % 8]
    end

    # Validates that a bit position is within the message boundaries.
    #
    # @param [Integer] bit_pos The bit position to validate
    # @param [Integer] bytes_size The size of the message in bytes
    # @return [void]
    # @raise [ArgumentError] If the bit position is out of bounds
    def validate_bit_position(bit_pos, bytes_size)
      byte_index = bit_pos / 8
      return unless byte_index >= bytes_size || byte_index.negative?

      raise ArgumentError, "Bit position #{bit_pos} out of bounds"
    end

    # Updates a specific bit within a byte in the message array.
    #
    # Sets or clears the specified bit within the target byte, initializing
    # the byte to 0 if it hasn't been set yet.
    #
    # @param [Array<Integer>] bytes The message byte array to modify
    # @param [Integer] byte_index The index of the byte to modify
    # @param [Integer] bit_index The bit position within the byte (0-7)
    # @param [Integer] bit The bit value to set (0 or 1)
    # @return [void]
    def update_byte_with_bit(bytes, byte_index, bit_index, bit)
      bytes[byte_index] ||= 0
      if bit == 1
        bytes[byte_index] |= (1 << bit_index)
      else
        bytes[byte_index] &= ~(1 << bit_index)
      end
    end

    # Extracts the signal value from the message byte array.
    #
    # This is the main decoding method that coordinates bit extraction
    # and sign conversion.
    #
    # @param [Array<Integer>] bytes The message byte array to decode from
    # @return [Integer] The raw integer value extracted from the message
    def extract_bits(bytes)
      value = read_bits_from_bytes(bytes)
      convert_to_signed_if_needed(value)
    end

    # Reads the raw bits from the message byte array.
    #
    # Extracts each bit of the signal from the message bytes, building
    # up the raw integer value bit by bit.
    #
    # @param [Array<Integer>] bytes The message byte array to read from
    # @return [Integer] The raw unsigned integer value
    def read_bits_from_bytes(bytes)
      value = 0
      length.times do |i|
        bit_pos = calculate_bit_position(i)
        byte_index, bit_index = calculate_byte_and_bit_indices(bit_pos)

        validate_extraction_bounds(bit_pos, bytes.size)

        bit = ((bytes[byte_index] || 0) >> bit_index) & 1
        value |= (bit << i)
      end
      value
    end

    # Validates bit position during extraction to ensure it's within bounds.
    #
    # @param [Integer] bit_pos The bit position to validate
    # @param [Integer] bytes_size The size of the message in bytes
    # @return [void]
    # @raise [ArgumentError] If the bit position is out of bounds
    def validate_extraction_bounds(bit_pos, bytes_size)
      byte_index = bit_pos / 8
      return unless byte_index >= bytes_size || byte_index.negative?

      raise ArgumentError, "Bit position #{bit_pos} out of bounds during extraction"
    end

    # Converts unsigned value to signed if the signal is signed and the MSB is set.
    #
    # For signed signals, checks if the most significant bit is set and
    # converts the value from two's complement representation to a negative integer.
    #
    # @param [Integer] value The unsigned integer value to potentially convert
    # @return [Integer] The final signed or unsigned value
    def convert_to_signed_if_needed(value)
      if sign == :signed && value[length - 1] == 1
        value - (1 << length)
      else
        value
      end
    end
  end
end
