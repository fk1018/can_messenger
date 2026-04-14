# messenger_spec.rb
# frozen_string_literal: true

require_relative "../../test_helper"
require "logger"
require "stringio"

RSpec.describe CanMessenger::Messenger do
  let(:interface) { "can0" }
  let(:log_output) { StringIO.new }
  let(:silent_logger) { Logger.new(log_output) }
  let(:mock_socket) { instance_double("Socket", write: nil, close: nil) }
  let(:mock_adapter) do
    instance_double(CanMessenger::Adapter::Base,
                    open_socket: mock_socket,
                    build_can_frame: "frame",
                    receive_message: nil)
  end
  subject(:messenger) { described_class.new(interface_name: interface, logger: silent_logger, adapter: mock_adapter) }

  describe "#initialize" do
    it "sets the interface instance variable" do
      expect(messenger.instance_variable_get(:@interface_name)).to eq(interface)
    end

    it "initializes listening as true" do
      expect(messenger.instance_variable_get(:@listening)).to be true
    end

    it "instantiates an adapter when a class is provided" do
      adapter_class = Class.new do
        attr_reader :args

        def initialize(interface_name:, logger:, endianness:)
          @args = { interface_name: interface_name, logger: logger, endianness: endianness }
        end
      end

      instance = described_class.new(
        interface_name: interface,
        logger: silent_logger,
        adapter: adapter_class,
        endianness: :little
      )
      adapter = instance.instance_variable_get(:@adapter)

      expect(adapter).to be_a(adapter_class)
      expect(adapter.args).to eq(interface_name: interface, logger: silent_logger, endianness: :little)
    end
  end

  describe "#send_can_message" do
    it "builds and writes a frame via the adapter" do
      expect(mock_adapter).to receive(:build_can_frame).with(
        id: 0x123,
        data: [0x01],
        extended_id: false,
        can_fd: false
      ).and_return("frame")
      expect(mock_socket).to receive(:write).with("frame")
      messenger.send_can_message(id: 0x123, data: [0x01])
    end

    it "re-raises ArgumentError from the adapter" do
      allow(mock_adapter).to receive(:build_can_frame).and_raise(ArgumentError, "bad frame")
      expect { messenger.send_can_message(id: 0x123, data: [0x01]) }.to raise_error(ArgumentError, "bad frame")
    end

    it "logs errors when sending fails" do
      allow(mock_adapter).to receive(:build_can_frame).and_raise(StandardError, "boom")
      expect(silent_logger).to receive(:error).with(/Error sending CAN message/)
      messenger.send_can_message(id: 0x123, data: [0x01])
    end
  end

  describe "#send_dbc_message" do
    let(:dbc) { instance_double(CanMessenger::DBC) }

    it "raises when dbc is nil" do
      expect { messenger.send_dbc_message(message_name: "Example", signals: {}, dbc: nil) }
        .to raise_error(ArgumentError, "dbc is required")
    end

    it "encodes and sends the message" do
      allow(dbc).to receive(:encode_can).and_return(id: 0x321, data: [0x11])
      expect(messenger).to receive(:send_can_message).with(id: 0x321, data: [0x11], extended_id: false, can_fd: nil)
      messenger.send_dbc_message(message_name: "Example", signals: { speed: 1 }, dbc: dbc)
    end

    it "sends DBC-defined extended frames with a normalized ID" do
      allow(dbc).to receive(:encode_can).and_return(id: 0x80000123, data: [0x11])
      expect(messenger).to receive(:send_can_message).with(id: 0x123, data: [0x11], extended_id: true, can_fd: nil)
      messenger.send_dbc_message(message_name: "Example", signals: { speed: 1 }, dbc: dbc)
    end

    it "logs errors when encoding fails" do
      allow(dbc).to receive(:encode_can).and_raise(StandardError, "boom")
      expect(silent_logger).to receive(:error).with(/Error sending DBC message/)
      messenger.send_dbc_message(message_name: "Example", signals: {}, dbc: dbc)
    end
  end

  describe "#start_listening" do
    it "yields received messages" do
      msg = { id: 1, data: [0xAA], extended: false }
      allow(mock_adapter).to receive(:receive_message).and_return(msg, nil)
      received = []
      messenger.start_listening do |message|
        received << message
        messenger.stop_listening
      end
      expect(received).to eq([msg])
    end

    it "logs an error when no block is given" do
      expect(silent_logger).to receive(:error).with(/No block provided/)
      messenger.start_listening
    end

    it "raises for unsupported filter values before opening a socket" do
      expect(mock_adapter).not_to receive(:open_socket)

      expect do
        messenger.start_listening(filter: "0x123") { |_| nil }
      end.to raise_error(ArgumentError, /filter must be nil, an Integer, a Range of Integers, or an Array of Integers/)
    end

    it "continues listening after a callback error" do
      msg = { id: 1, data: [0xAA], extended: false }
      allow(mock_adapter).to receive(:receive_message).and_return(msg, msg)
      received = 0

      messenger.start_listening do |_message|
        received += 1
        raise "boom" if received == 1

        messenger.stop_listening
      end

      expect(received).to eq(2)
    end
  end

  describe "#with_socket" do
    it "yields the opened socket and closes it" do
      yielded = nil
      messenger.send(:with_socket) { |s| yielded = s }
      expect(yielded).to eq(mock_socket)
      expect(mock_socket).to have_received(:close)
    end

    it "logs an error when socket cannot be opened" do
      allow(mock_adapter).to receive(:open_socket).and_return(nil)
      expect(silent_logger).to receive(:error).with(/Failed to open socket/)
      executed = false
      messenger.send(:with_socket) { executed = true }
      expect(executed).to be false
    end
  end

  describe "#stop_listening" do
    it "sets @listening to false" do
      messenger.stop_listening
      expect(messenger.instance_variable_get(:@listening)).to be false
    end
  end

  describe "#matches_filter?" do
    it "returns true when the filter is nil" do
      expect(messenger.send(:matches_filter?, message_id: 0x123, filter: nil)).to be(true)
    end

    it "matches a single CAN ID" do
      expect(messenger.send(:matches_filter?, message_id: 0x123, filter: 0x123)).to be(true)
      expect(messenger.send(:matches_filter?, message_id: 0x124, filter: 0x123)).to be(false)
    end

    it "matches a range of CAN IDs" do
      expect(messenger.send(:matches_filter?, message_id: 0x123, filter: (0x100..0x200))).to be(true)
      expect(messenger.send(:matches_filter?, message_id: 0x300, filter: (0x100..0x200))).to be(false)
    end

    it "matches an array of CAN IDs" do
      expect(messenger.send(:matches_filter?, message_id: 0x123, filter: [0x123, 0x124])).to be(true)
      expect(messenger.send(:matches_filter?, message_id: 0x126, filter: [0x123, 0x124])).to be(false)
    end

    it "raises for arrays with non-integer values" do
      expect do
        messenger.send(:matches_filter?, message_id: 0x123, filter: [0x123, "0x124"])
      end.to raise_error(ArgumentError, /only Integer values/)
    end

    it "raises for ranges with non-integer endpoints" do
      expect do
        messenger.send(:validate_filter!, "0x100".."0x200")
      end.to raise_error(ArgumentError, /Integer endpoints/)
    end
  end

  describe "#process_message" do
    let(:dbc) { instance_double(CanMessenger::DBC) }

    it "adds decoded data when dbc is provided" do
      message = { id: 0x123, data: [0x01] }
      decoded = { name: "Example", signals: { speed: 1 } }
      allow(mock_adapter).to receive(:receive_message).and_return(message)
      allow(dbc).to receive(:decode_can).and_return(decoded)

      received = nil
      messenger.send(:process_message, mock_socket, nil, false, dbc) { |msg| received = msg }

      expect(received[:decoded]).to eq(decoded)
    end

    it "yields the raw frame with decode_error when DBC decoding raises" do
      message = { id: 0x123, data: [], extended: false }
      allow(mock_adapter).to receive(:receive_message).and_return(message)
      allow(dbc).to receive(:decode_can).and_raise(ArgumentError, "bad decode")
      expect(silent_logger).to receive(:error).with(/Error decoding DBC message 0x123: bad decode/)

      received = nil
      messenger.send(:process_message, mock_socket, nil, false, dbc) { |msg| received = msg }

      expect(received).to include(id: 0x123, data: [], extended: false)
      expect(received[:decode_error]).to eq(class: "ArgumentError", message: "bad decode")
      expect(received).not_to have_key(:decoded)
    end

    it "reconstructs the extended DBC ID before decoding" do
      message = { id: 0x123, data: [0x01], extended: true }
      decoded = { name: "Example", signals: { speed: 1 } }
      allow(mock_adapter).to receive(:receive_message).and_return(message)
      expect(dbc).to receive(:decode_can).with(0x80000123, [0x01]).and_return(decoded)

      received = nil
      messenger.send(:process_message, mock_socket, nil, false, dbc) { |msg| received = msg }

      expect(received[:decoded]).to eq(decoded)
    end

    it "logs unexpected errors" do
      allow(mock_adapter).to receive(:receive_message).and_raise(StandardError, "boom")
      expect(silent_logger).to receive(:error).with(/Unexpected error in listening loop/)
      messenger.send(:process_message, mock_socket, nil, false, nil) { |_| nil }
    end
  end
end
