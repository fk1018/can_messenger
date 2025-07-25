# frozen_string_literal: true

module CanMessenger
  # DBC parser for defining CAN messages and signals
  class DBC
    attr_reader :messages

    def self.load(path)
      new(File.read(path))
    end

    def initialize(content = "")
      @messages = {}
      parse(content) unless content.empty?
    end

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

    def parse_message_line(line)
      return unless (m = line.match(/^BO_\s+(\d+)\s+(\w+)\s*:\s*(\d+)/))

      id = m[1].to_i
      name = m[2]
      dlc = m[3].to_i
      Message.new(id, name, dlc)
    end

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

    def encode_can(name, values)
      msg = @messages[name]
      raise ArgumentError, "Unknown message #{name}" unless msg

      { id: msg.id, data: msg.encode(values) }
    end

    def decode_can(id, data)
      msg = @messages.values.find { |m| m.id == id }
      return nil unless msg

      { name: msg.name, signals: msg.decode(data) }
    end
  end

  # Represents a CAN message definition from a DBC file.
  class Message
    attr_reader :id, :name, :dlc, :signals

    def initialize(id, name, dlc)
      @id = id
      @name = name
      @dlc = dlc
      @signals = []
    end

    def encode(values)
      bytes = Array.new(@dlc, 0)
      @signals.each do |sig|
        next unless values.key?(sig.name.to_sym) || values.key?(sig.name.to_s)

        v = values[sig.name.to_sym] || values[sig.name.to_s]
        sig.encode(bytes, v)
      end
      bytes
    end

    def decode(data)
      res = {}
      @signals.each do |sig|
        res[sig.name.to_sym] = sig.decode(data)
      end
      res
    end
  end

  # Represents a signal within a CAN message.
  class Signal
    attr_reader :name, :start_bit, :length, :endianness, :sign, :factor, :offset

    def initialize(name, start_bit:, length:, endianness:, sign:, factor:, offset:) # rubocop:disable Metrics/ParameterLists
      @name = name
      @start_bit = start_bit
      @length = length
      @endianness = endianness
      @sign = sign
      @factor = factor
      @offset = offset
    end

    def encode(bytes, value)
      raw = ((value - offset) / factor).round
      validate_signal_bounds(bytes.size)
      insert_bits(bytes, raw)
    end

    def decode(bytes)
      raw = extract_bits(bytes)
      (raw * factor) + offset
    end

    private

    def validate_signal_bounds(message_size_bytes)
      max_bit = start_bit + length - 1
      max_allowed_bit = (message_size_bytes * 8) - 1

      raise ArgumentError, "Signal #{name}: start_bit (#{start_bit}) cannot be negative" if start_bit.negative?

      return unless max_bit > max_allowed_bit

      raise ArgumentError,
            "Signal #{name}: signal bits #{start_bit}..#{max_bit} exceed message size " \
            "(#{message_size_bytes} bytes = #{max_allowed_bit + 1} bits)"
    end

    def insert_bits(bytes, raw) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      # Handle signed values: convert negative to two's complement
      raw = (1 << length) + raw if sign == :signed && raw.negative?

      # Ensure the value fits in the specified bit length
      raw &= (1 << length) - 1

      length.times do |i|
        bit = (raw >> i) & 1
        bit_pos = endianness == :little ? start_bit + i : start_bit - i
        byte_index = bit_pos / 8
        bit_index = bit_pos % 8

        # Validate bounds before accessing array
        raise ArgumentError, "Bit position #{bit_pos} out of bounds" if byte_index >= bytes.size || byte_index.negative?

        bytes[byte_index] ||= 0
        if bit == 1
          bytes[byte_index] |= (1 << bit_index)
        else
          bytes[byte_index] &= ~(1 << bit_index)
        end
      end
    end

    def extract_bits(bytes) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      value = 0
      length.times do |i|
        bit_pos = endianness == :little ? start_bit + i : start_bit - i
        byte_index = bit_pos / 8
        bit_index = bit_pos % 8

        # Validate bounds before accessing array
        next if byte_index >= bytes.size || byte_index.negative?

        bit = ((bytes[byte_index] || 0) >> bit_index) & 1
        value |= (bit << i)
      end
      if sign == :signed && value[length - 1] == 1
        value - (1 << length)
      else
        value
      end
    end
  end
end
