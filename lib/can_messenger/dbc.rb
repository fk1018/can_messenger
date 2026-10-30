# frozen_string_literal: true

module CanMessenger
  # DBC (Database CAN) Parser and Encoder/Decoder
  #
  # This class provides functionality to parse DBC files and encode/decode CAN messages
  # according to the signal definitions. DBC files are a standard way to describe
  # CAN network communication.
  # Integer signals support signed or unsigned values, both byte orders, and scaling.
  # Unsupported floating-point signal declarations raise instead of being decoded as integers.
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
  class DBC # rubocop:disable Metrics/ClassLength
    # Metadata directive names that can be skipped; matching uses complete tokens.
    IGNORED_LINE_PREFIXES = %w[
      BO_TX_BU_
      VERSION
      NS_
      BS_
      BU_
      CM_
      VAL_
      BA_
      BA_DEF_
      BA_DEF_DEF_
    ].freeze

    # Numeric tokens allow a sign, decimal point, and optional scientific exponent.
    NUMBER_PATTERN = /[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?/
    # Message headers provide the stored identifier, name, payload size, and sender.
    MESSAGE_LINE_PATTERN = /^BO_\s+(\d+)\s+(\w+)\s*:\s*(\d+)\s+\S.*$/
    # Capture the signal layout and scaling; byte order is restricted to @0 or @1.
    SIGNAL_LINE_PATTERN = /^SG_\s+(\w+)\s*:\s*(\d+)\|(\d+)@([01])([+-])\s*
                           \(\s*(#{NUMBER_PATTERN})\s*,\s*(#{NUMBER_PATTERN})\s*\)/x
    # Type 0 is an integer; types 1 and 2 declare unsupported IEEE float and double signals.
    SIGNAL_VALUE_TYPE_PATTERN = /\ASIG_VALTYPE_\s+\d+\s+\w+\s*:\s*(\d+)\s*;\z/

    # @return [Hash<String, Message>] Parsed message definitions keyed by their names
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
    # @return [void]
    # @raise [ArgumentError] If the content contains a malformed or unsupported definition
    def initialize(content = "")
      @messages = {}
      parse(content) unless content.empty?
    end

    # Parses DBC content and populates the messages hash.
    #
    # This method processes each line of the DBC content, identifying message
    # definitions (BO_) and signal definitions (SG_). It builds a complete
    # message structure with all associated signals.
    # Existing messages are retained unless a new definition uses the same name.
    #
    # @param [String] content The DBC file content to parse
    # @return [void]
    # @raise [ArgumentError] If a definition is malformed or unsupported, with line number and text
    def parse(content) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      current = nil
      in_namespace_section = false

      # The parser is intentionally strict so malformed DBC files fail early with line context.
      # We still ignore a small allowlist of standard metadata directives that do not affect encode/decode.
      content.each_line.with_index(1) do |line, line_number|
        stripped_line = line.strip

        if in_namespace_section
          next if line.match?(/^\s+\S/)

          in_namespace_section = false
        end

        next if stripped_line.empty?

        if ignored_line?(stripped_line)
          in_namespace_section = stripped_line.start_with?("NS_")
          next
        end

        if stripped_line.start_with?("BO_")
          msg = parse_message_line(stripped_line)
          raise_parse_error("Invalid message definition", line_number, stripped_line) unless msg

          current = msg
          @messages[msg.name] = msg
        elsif stripped_line.start_with?("SG_")
          raise_parse_error("Signal definition without a current message", line_number, stripped_line) unless current

          sig = parse_signal_line(stripped_line, current)
          raise_parse_error("Invalid signal definition", line_number, stripped_line) unless sig

          current.signals << sig
        elsif stripped_line.start_with?("SIG_VALTYPE_")
          validate_signal_value_type(stripped_line, line_number)
        else
          raise_parse_error("Unsupported or malformed DBC line", line_number, stripped_line)
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
      return unless (m = line.match(MESSAGE_LINE_PATTERN))

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
    # @return [Signal, nil] The signal, or nil if its layout or scaling cannot be parsed
    def parse_signal_line(line, _current) # rubocop:disable Metrics/MethodLength
      return unless (m = line.match(SIGNAL_LINE_PATTERN))

      factor = parse_number(m[6])
      offset = parse_number(m[7])
      return unless factor && offset
      return if factor.zero?

      Signal.new(
        m[1],
        start_bit: m[2].to_i,
        length: m[3].to_i,
        endianness: m[4] == "1" ? :little : :big,
        sign: m[5] == "-" ? :signed : :unsigned,
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
    # @raise [ArgumentError] If the name is unknown, a value is out of range, or a signal exceeds the payload
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
    # The identifier must match the stored DBC ID, including its extended-frame
    # flag when present; Messenger handles this conversion for received frames.
    #
    # @param [Integer] id The CAN message ID
    # @param [Array<Integer>] data The CAN message data bytes
    # @return [Hash, nil] A hash containing :name (String) and :signals (Hash), or nil if no matching message
    # @raise [ArgumentError] If a signal references bits outside the supplied payload
    #
    # @example
    #   decoded = dbc.decode_can(0x123, [0x09, 0xC4, 0xAB, 0x00, 0x00, 0x00, 0x00, 0x00])
    #   # => { name: 'EngineData', signals: { RPM: 2500.0, Temperature: 85.5 } }
    def decode_can(id, data)
      msg = @messages.values.find { |m| m.id == id }
      return nil unless msg

      { name: msg.name, signals: msg.decode(data) }
    end

    private

    # Checks whether a line begins with an explicitly supported metadata directive.
    #
    # Comparing the complete token prevents unsupported names such as BA_UNKNOWN_
    # from being mistaken for the supported BA_ directive.
    #
    # @param [String] line The stripped DBC line
    # @return [Boolean] Whether the parser can skip this directive
    def ignored_line?(line)
      IGNORED_LINE_PREFIXES.include?(line.split(/[\s:]/, 2).first)
    end

    # Parses a scaling token without losing precision for integral values.
    #
    # Decimal and exponent spellings such as "1.0" and "1e0" remain exact integers.
    # Fractional values use Float to retain the existing scaling behavior.
    #
    # @param [String] value A numeric token matched by the signal pattern
    # @return [Integer, Float, nil] The parsed value, or nil if a fractional value is not finite
    def parse_number(value)
      value = value.sub(/\.(?=[eE]|\z)/, ".0")
      exact = Rational(value)
      return exact.to_i if exact.denominator == 1

      number = Float(value)
      number if number.finite?
    end

    # Validates a SIG_VALTYPE_ declaration and rejects unsupported signal representations.
    #
    # Only integer type 0 is supported. Accepting IEEE types 1 or 2 without handling
    # their binary representation would silently change the encoded or decoded value.
    #
    # @param [String] line The stripped signal-type declaration
    # @param [Integer] line_number The one-based line number in the DBC content
    # @return [void]
    # @raise [ArgumentError] If the declaration is malformed or names an unsupported type
    def validate_signal_value_type(line, line_number)
      match = line.match(SIGNAL_VALUE_TYPE_PATTERN)
      raise_parse_error("Invalid signal value type definition", line_number, line) unless match
      return if match[1] == "0"

      raise_parse_error("Unsupported signal value type #{match[1]} (only integer type 0 is supported)",
                        line_number, line)
    end

    # Raises a parse error with enough source context to locate the definition.
    #
    # @param [String] reason The explanation of the parse failure
    # @param [Integer] line_number The one-based line number in the DBC content
    # @param [String] line The offending DBC line
    # @return [void]
    # @raise [ArgumentError] Always, with the reason, line number, and offending text
    def raise_parse_error(reason, line_number, line)
      raise ArgumentError, "#{reason} at line #{line_number}: #{line}"
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
    # @param [Integer] id The stored CAN ID, including the DBC extended-frame flag when present
    # @param [String] name The symbolic name of the message
    # @param [Integer] dlc Payload size in bytes; at most 8 for classic CAN or 64 for CAN FD
    # @return [void]
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
    # The new payload is filled with zeros, and only supplied signal values are written.
    #
    # @param [Hash<Symbol|String, Numeric>] values Signal names mapped to their values
    # @return [Array<Integer>] Array of bytes representing the encoded message
    # @raise [ArgumentError] If a value is out of range or a signal exceeds the payload size
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
    # @return [Hash<Symbol, Numeric>] Signal names mapped to their decoded values
    # @raise [ArgumentError] If a signal references bits outside the supplied payload
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
    # @param [Numeric] factor Scaling factor to convert raw value to engineering units
    # @param [Numeric] offset Offset to add after scaling
    # @return [void]
    def initialize(name, start_bit:, length:, endianness:, sign:, factor:, offset:) # rubocop:disable Metrics/ParameterLists
      @name = name
      @start_bit = start_bit
      @length = length
      @endianness = endianness
      @sign = sign
      @factor = normalize_integral_number(factor)
      @offset = normalize_integral_number(offset)
    end

    # Encodes a value into the message byte array at this signal's bit position.
    #
    # Converts the engineering unit value to a raw integer using the signal's
    # factor and offset, then places the bits into the appropriate positions
    # within the message bytes.
    # Fractional raw values round to the nearest integer, with ties away from zero.
    #
    # @param [Array<Integer>] bytes The message byte array to modify
    # @param [Numeric] value The engineering unit value to encode
    # @return [void]
    # @raise [ArgumentError] If the value is out of range or signal exceeds message bounds
    def encode(bytes, value)
      raw = (value - offset).quo(factor).round
      validate_signal_bounds(bytes.size)
      insert_bits(bytes, raw)
    end

    # Decodes this signal's value from the message byte array.
    #
    # Extracts the raw integer value from the appropriate bit positions,
    # then applies the signal's scaling (factor and offset) to convert
    # it to engineering units.
    # Integer factors and offsets preserve exact Integer results; fractional Float scaling returns a Float.
    #
    # @param [Array<Integer>] bytes The message byte array to decode from
    # @return [Numeric] The decoded value in engineering units
    # @raise [ArgumentError] If a signal bit falls outside the supplied payload
    def decode(bytes)
      raw = extract_bits(bytes)
      (raw * factor) + offset
    end

    private

    # Converts integral Float scaling values to Integer without changing fractional values.
    #
    # Keeping identity scaling such as 1.0 and 0.0 integral avoids rounding large
    # signal values through floating-point arithmetic.
    #
    # @param [Numeric] number The factor or offset supplied to the signal constructor
    # @return [Numeric] An Integer for integral finite Floats, otherwise the original number
    def normalize_integral_number(number)
      return number unless number.is_a?(Float) && number.finite? && number.denominator == 1

      number.to_i
    end

    # Validates that the signal fits within the message boundaries.
    #
    # Ensures that all bits used by this signal fall within the message's
    # data length code (DLC) boundaries.
    #
    # @param [Integer] message_size_bytes The size of the message in bytes
    # @return [void]
    # @raise [ArgumentError] If signal bits exceed message boundaries or start_bit is negative
    def validate_signal_bounds(message_size_bytes)
      raise ArgumentError, "Signal #{name}: start_bit (#{start_bit}) cannot be negative" if start_bit.negative?
      raise ArgumentError, "Signal #{name}: length (#{length}) must be positive" if length <= 0

      max_allowed_bit = max_allowed_bit_for(message_size_bytes)
      invalid_position = invalid_bit_position(max_allowed_bit)
      return unless invalid_position

      raise ArgumentError,
            "Signal #{name}: bit position #{invalid_position} exceeds message size " \
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
      return unless sign == :unsigned

      raise ArgumentError, "Unsigned value cannot be negative: #{raw}" if raw.negative?

      max_val = (1 << length) - 1
      return if raw <= max_val

      raise ArgumentError,
            "Unsigned value #{raw} out of range [0..#{max_val}] for #{length}-bit field"
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
        # DBC big-endian (`@0`) start_bit is in sawtooth numbering and points at the
        # signal MSB. Convert to sequential network numbering, move toward the LSB,
        # then convert back to the little-endian bit index used by byte writes.
        network_start = sawtooth_to_network_bitnum(start_bit)
        network_bit = network_start + (length - 1 - bit_offset)
        sawtooth_to_network_bitnum(network_bit)
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
      return value unless sign == :signed && length.positive?

      msb_set = (value >> (length - 1)).allbits?(1)
      msb_set ? value - (1 << length) : value
    end

    # Reverses the bit numbering within each byte for Motorola signal positions.
    #
    # DBC sawtooth numbering labels a byte's least significant bit as 0, whereas
    # sequential network numbering starts with its most significant bit. Applying
    # this conversion twice returns the original position.
    #
    # @param [Integer] bitnum The absolute bit position in either numbering scheme
    # @return [Integer] The corresponding position in the other scheme
    def sawtooth_to_network_bitnum(bitnum)
      (8 * (bitnum / 8)) + (7 - (bitnum % 8))
    end

    # Finds the first signal bit that falls outside the payload boundaries.
    #
    # Checks mapped positions so Motorola signals spanning multiple bytes use
    # the same bounds rules as their encoding and decoding paths.
    #
    # @param [Integer] max_allowed_bit The highest valid bit index in the payload
    # @return [Integer, nil] The first invalid position encountered, or nil if all positions fit
    def invalid_bit_position(max_allowed_bit)
      length.times do |i|
        bit_pos = calculate_bit_position(i)
        return bit_pos if bit_pos.negative? || bit_pos > max_allowed_bit
      end

      nil
    end

    # Converts a payload size to its highest valid zero-based bit index.
    #
    # @param [Integer] message_size_bytes The payload size in bytes
    # @return [Integer] The highest bit index, or -1 for an empty payload
    def max_allowed_bit_for(message_size_bytes)
      (message_size_bytes * 8) - 1
    end
  end
end
