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
  end
end
