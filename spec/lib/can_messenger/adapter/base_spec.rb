# frozen_string_literal: true

require_relative "../../../test_helper"
require "logger"

RSpec.describe CanMessenger::Adapter::Base do
  subject(:adapter) { described_class.new(interface_name: "can0", logger: Logger.new(nil)) }

  describe ".native_endianness" do
    it "returns :big when native pack matches network order" do
      allow(described_class).to receive(:pack_uint).and_wrap_original do |original, value, template|
        mapping = { "I" => "N", "V" => "V", "N" => "N" }
        mapping.fetch(template) { original.call(value, template) }
      end

      expect(described_class.native_endianness).to eq(:big)
    end

    it "falls back to byte inspection when native order is unknown" do
      allow(described_class).to receive(:pack_uint).and_wrap_original do |original, value, template|
        case template
        when "I" then "X"
        when "V" then "V"
        when "N" then "N"
        else original.call(value, template)
        end
      end

      expect(described_class.native_endianness).to eq(:big)
    end
  end

  it "defaults to native endianness" do
    expect(adapter.endianness).to eq(described_class.native_endianness)
  end

  it "raises NotImplementedError for open_socket" do
    expect { adapter.open_socket }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for build_can_frame" do
    expect { adapter.build_can_frame(id: 1, data: []) }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for receive_message" do
    expect { adapter.receive_message(socket: nil) }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for parse_frame" do
    expect { adapter.parse_frame(frame: "") }.to raise_error(NotImplementedError)
  end
end
