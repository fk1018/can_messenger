# frozen_string_literal: true

require_relative "../../test_helper"
require "tempfile"

RSpec.describe CanMessenger::DBC do
  let(:dbc_text) do
    <<~DBC
      BO_ 256 Example: 8 ExampleNode
      SG_ Speed : 0|8@1+ (1,0) [0|255] "" Vector__XXX
      SG_ Temp : 8|8@1+ (0.5,0) [0|127.5] "" Vector__XXX
    DBC
  end

  describe ".new" do
    it "parses messages and signals from text" do
      dbc = described_class.new(dbc_text)
      expect(dbc.messages.keys).to include("Example")
      msg = dbc.messages["Example"]
      expect(msg.id).to eq(256)
      expect(msg.signals.map(&:name)).to match_array(%w[Speed Temp])
    end

    it "handles multiple message definitions" do
      text = <<~DBC
        BO_ 1 Msg1: 1 Node
        SG_ A : 0|8@1+ (1,0) [0|255] "" Vector__XXX
        BO_ 2 Msg2: 1 Node
        SG_ B : 0|8@1+ (1,0) [0|255] "" Vector__XXX
      DBC
      multi = described_class.new(text)
      expect(multi.messages.keys).to match_array(%w[Msg1 Msg2])
    end
  end

  describe ".load" do
    it "loads a DBC file from disk" do
      Tempfile.create(["test", ".dbc"]) do |file|
        file.write(dbc_text)
        file.flush
        dbc = described_class.load(file.path)
        expect(dbc.messages["Example"]).not_to be_nil
      end
    end
  end

  describe "#encode_can and #decode_can" do
    let(:dbc) { described_class.new(dbc_text) }

    it "encodes signal values into CAN bytes and decodes them back" do
      frame = dbc.encode_can("Example", Speed: 10, Temp: 20)
      expect(frame[:id]).to eq(256)
      expect(frame[:data].first(2)).to eq([10, 40])

      decoded = dbc.decode_can(frame[:id], frame[:data])
      expect(decoded[:name]).to eq("Example")
      expect(decoded[:signals][:Speed]).to eq(10)
      expect(decoded[:signals][:Temp]).to eq(20)
    end

    it "encodes negative signed values correctly" do
      text = <<~DBC
        BO_ 1 Neg: 1 Example
        SG_ Val : 0|8@1- (1,0) [-128|127] "" Vector__XXX
      DBC
      neg_dbc = described_class.new(text)
      frame = neg_dbc.encode_can("Neg", Val: -1)
      expect(frame[:data].first).to eq(0xFF)
    end

    it "handles big endian signals correctly" do
      text = <<~DBC
        BO_ 1 BigEndian: 2 Node
        SG_ Val : 0|8@0+ (1,0) [0|255] "" Vector__XXX
      DBC
      be_dbc = described_class.new(text)
      frame = be_dbc.encode_can("BigEndian", Val: 42)
      decoded = be_dbc.decode_can(frame[:id], frame[:data])
      expect(decoded[:signals][:Val]).to eq(42.0)
    end

    it "handles big endian signals crossing byte boundaries" do
      text = <<~DBC
        BO_ 1 Cross: 3 Node
        SG_ A : 12|12@0+ (1,0) [0|4095] "" Vector__XXX
      DBC
      cross_dbc = described_class.new(text)
      frame = cross_dbc.encode_can("Cross", A: 0xabc)
      expect(frame[:data].first(3)).to eq([0xD5, 0x03, 0x00])
      decoded = cross_dbc.decode_can(frame[:id], frame[:data])
      expect(decoded[:signals][:A]).to eq(0xabc)
    end

    it "applies factor and offset correctly" do
      text = <<~DBC
        BO_ 1 Scaled: 2 Node
        SG_ Temp : 0|8@1+ (0.5,10) [10|137.5] "" Vector__XXX
      DBC
      scaled_dbc = described_class.new(text)
      frame = scaled_dbc.encode_can("Scaled", Temp: 25)
      expect(frame[:data].first).to eq(30) # (25-10)/0.5 = 30

      decoded = scaled_dbc.decode_can(frame[:id], frame[:data])
      expect(decoded[:signals][:Temp]).to eq(25.0)
    end

    it "handles signals with different bit lengths" do
      text = <<~DBC
        BO_ 1 MultiLength: 2 Node
        SG_ Short : 0|4@1+ (1,0) [0|15] "" Vector__XXX
        SG_ Long : 4|12@1+ (1,0) [0|4095] "" Vector__XXX
      DBC
      ml_dbc = described_class.new(text)
      frame = ml_dbc.encode_can("MultiLength", Short: 5, Long: 1000)

      decoded = ml_dbc.decode_can(frame[:id], frame[:data])
      expect(decoded[:signals][:Short]).to eq(5)
      expect(decoded[:signals][:Long]).to eq(1000)
    end

    it "raises error for unknown message" do
      expect { dbc.encode_can("Unknown", Value: 1) }.to raise_error(ArgumentError, "Unknown message Unknown")
    end

    it "returns nil for unknown CAN ID during decode" do
      result = dbc.decode_can(999, [1, 2, 3])
      expect(result).to be_nil
    end

    it "raises error for negative unsigned values" do
      expect do
        dbc.encode_can("Example", Speed: -1)
      end.to raise_error(ArgumentError, "Unsigned value cannot be negative: -1")
    end

    it "raises error for out of range signed values" do
      text = <<~DBC
        BO_ 1 Signed: 1 Node
        SG_ Val : 0|8@1- (1,0) [-128|127] "" Vector__XXX
      DBC
      signed_dbc = described_class.new(text)
      expect { signed_dbc.encode_can("Signed", Val: -200) }.to raise_error(ArgumentError, /out of range/)
      expect { signed_dbc.encode_can("Signed", Val: 200) }.to raise_error(ArgumentError, /out of range/)
    end

    it "raises error for signals exceeding message bounds" do
      text = <<~DBC
        BO_ 1 OutOfBounds: 1 Node
        SG_ Val : 8|8@1+ (1,0) [0|255] "" Vector__XXX
      DBC
      oob_dbc = described_class.new(text)
      expect { oob_dbc.encode_can("OutOfBounds", Val: 1) }.to raise_error(ArgumentError, /exceed message size/)
    end

    it "raises error for negative start bit" do
      # This would require direct Signal construction since regex won't allow negative
      signal = CanMessenger::Signal.new("Test", start_bit: -1, length: 8, endianness: :little, sign: :unsigned,
                                                factor: 1, offset: 0)
      expect { signal.encode([0], 1) }.to raise_error(ArgumentError, /cannot be negative/)
    end

    it "raises error for bit position out of bounds during extraction" do
      text = <<~DBC
        BO_ 1 Extract: 1 Node
        SG_ Val : 8|8@1+ (1,0) [0|255] "" Vector__XXX
      DBC
      ext_dbc = described_class.new(text)
      # Try to decode with insufficient data
      expect { ext_dbc.decode_can(1, []) }.to raise_error(ArgumentError, /out of bounds during extraction/)
    end

    it "handles string keys in encoding" do
      frame = dbc.encode_can("Example", "Speed" => 15, "Temp" => 25)
      expect(frame[:data].first(2)).to eq([15, 50])
    end

    it "skips unknown signals during encoding" do
      frame = dbc.encode_can("Example", Speed: 10, UnknownSignal: 99)
      expect(frame[:data].first).to eq(10)
    end

    it "handles empty DBC content" do
      empty_dbc = described_class.new("")
      expect(empty_dbc.messages).to be_empty
    end

    it "skips empty lines and comments" do
      text = <<~DBC

        BO_ 256 Example: 8 ExampleNode
        BO_TX_BU_ 256 : Node1,Node2;
        SG_ Speed : 0|8@1+ (1,0) [0|255] "" Vector__XXX

      DBC
      comment_dbc = described_class.new(text)
      expect(comment_dbc.messages.keys).to eq(["Example"])
    end
  end
end
