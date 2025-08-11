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
  end
end
