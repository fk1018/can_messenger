# messenger_spec.rb
# frozen_string_literal: true

require_relative "../../test_helper"
require "socket"
require "logger"
require "stringio"

RSpec.describe CanMessenger::Messenger do
  before(:all) do
    Socket.const_set(:CAN_RAW, 1) unless Socket.const_defined?(:CAN_RAW)
    Socket.const_set(:PF_CAN, 29) unless Socket.const_defined?(:PF_CAN)

    # Mock pack_sockaddr_can if it's not available
    unless Socket.respond_to?(:pack_sockaddr_can)
      def Socket.pack_sockaddr_can(_interface)
        "\x00" * 16 # Simulate a 16-byte packed sockaddr structure
      end
    end
  end

  let(:interface) { "can0" }
  # Create a silent logger that writes to a StringIO so no log output appears during tests.
  let(:log_output) { StringIO.new }
  let(:silent_logger) { Logger.new(log_output) }
  let(:socket) { described_class.new(interface_name: interface, logger: silent_logger) }

  before do
    allow(socket).to receive(:system).and_return(true)
  end

  # Define a consistent sample frame used across tests
  def sample_frame
    # 12-byte frame with 8-byte header and 4 bytes of data
    "#{[0x12345678].pack("L>")}\u0004#{"\x00" * 3}#{[0xDE, 0xAD, 0xBE, 0xEF].pack("C*")}"
  end

  describe "#initialize" do
    it "sets the interface instance variable" do
      expect(socket.instance_variable_get(:@interface_name)).to eq(interface)
    end

    it "initializes listening as true" do
      expect(socket.instance_variable_get(:@listening)).to be true
    end
  end

  describe "#send_can_message" do
    let(:mock_socket) { instance_double(Socket) }

    before do
      # Whenever the code calls `open_can_socket`, return our mock
      allow(socket).to receive(:open_can_socket).and_return(mock_socket)
      # We also expect the socket to be closed in `with_socket` ensure block
      allow(mock_socket).to receive(:close)
    end

    it "builds and writes a raw CAN frame to the socket" do
      expected_frame = [
        0x00, 0x00, 0x01, 0x23,  # ID in big-endian
        0x04, 0x00, 0x00, 0x00,  # DLC=4 plus 3 bytes pad
        0xDE, 0xAD, 0xBE, 0xEF,  # The 4 data bytes
        0x00, 0x00, 0x00, 0x00   # pad out to 8 data bytes
      ].pack("C*")

      expect(mock_socket).to receive(:write).with(expected_frame)

      # Call the method
      socket.send_can_message(id: 0x123, data: [0xDE, 0xAD, 0xBE, 0xEF])
    end

    context "when an error occurs during write" do
      it "logs the error and does not raise" do
        # Simulate an error on mock_socket.write
        allow(mock_socket).to receive(:write).and_raise(StandardError, "Test error")

        expect(silent_logger).to receive(:error).with(/Error sending CAN message \(ID: 291\): Test error/)
        expect { socket.send_can_message(id: 0x123, data: [0xDE, 0xAD, 0xBE, 0xEF]) }
          .not_to raise_error
      end
    end
    context "with an extended ID" do
      it "builds and writes a raw CAN frame with the EFF bit (bit 31) set" do
        # Suppose we have an extended ID = 0x1ABC
        # Setting extended_id: true should set bit 31 -> raw_id = 0x80000000 | 0x1ABC
        extended_id_value = 0x1ABC
        eff_bit = 0x80000000
        raw_id = extended_id_value | eff_bit

        # For big-endian, pack this in network order (N == L>):
        # ID bytes, DLC=4, 3 pad, then data, plus 4 padding data bytes
        expected_frame = [
          (raw_id >> 24) & 0xFF,
          (raw_id >> 16) & 0xFF,
          (raw_id >> 8)  & 0xFF,
          raw_id & 0xFF,

          0x04, 0x00, 0x00, 0x00,  # DLC=4 + 3 pad
          0xDE, 0xAD, 0xBE, 0xEF,  # 4 data bytes
          0x00, 0x00, 0x00, 0x00   # pad to 8 data bytes
        ].pack("C*")

        expect(mock_socket).to receive(:write).with(expected_frame)
        socket.send_can_message(id: extended_id_value, data: [0xDE, 0xAD, 0xBE, 0xEF], extended_id: true)
      end
    end

    context "when data length exceeds eight bytes" do
      it "raises ArgumentError" do
        expect do
          socket.send_can_message(id: 0x123, data: Array.new(9, 0xFF))
        end.to raise_error(ArgumentError)
      end
    end
  end

  describe "#start_listening" do
    let(:mock_socket) { instance_double(Socket) }

    before do
      allow(socket).to receive(:open_can_socket).and_return(mock_socket)
      allow(mock_socket).to receive(:close)
    end

    def capture_received_messages
      received_messages = []
      listener_thread = Thread.new do
        socket.start_listening do |message|
          received_messages << message
          socket.stop_listening # Stop once a message is received to prevent an infinite loop.
        end
      end
      listener_thread.join(1)
      received_messages
    end

    it "yields received messages to the block" do
      allow(mock_socket).to receive(:recv).and_return(sample_frame, nil)
      expect(capture_received_messages).to eq([{ id: 0x12345678, extended: false, data: [0xDE, 0xAD, 0xBE, 0xEF] }])
    end

    it "closes the socket after listening" do
      allow(mock_socket).to receive(:recv).and_return(nil)
      listener_thread = Thread.new { socket.start_listening { puts "Received message" } }
      sleep 0.2 # Let the listening loop run briefly
      socket.stop_listening
      listener_thread.join(1) # Wait for the thread to finish (with a timeout)
      expect(mock_socket).to have_received(:close)
    end

    it "handles IO::WaitReadable gracefully and terminates the thread" do
      allow(mock_socket).to receive(:recv).and_raise(IO::WaitReadable)

      listener_thread = Thread.new do
        socket.start_listening
      end

      sleep 0.2 # Let the thread run briefly.
      socket.stop_listening
      listener_thread.join(1)

      expect(listener_thread).not_to be_alive
    end

    it "handles StandardError gracefully and terminates the thread" do
      allow(mock_socket).to receive(:recv).and_raise(StandardError)

      listener_thread = Thread.new do
        socket.start_listening
      end

      sleep 0.2 # Let the thread run briefly.
      socket.stop_listening
      listener_thread.join(1)

      expect(listener_thread).not_to be_alive
    end

    it "can be started again after being stopped" do
      allow(mock_socket).to receive(:recv).and_return(sample_frame, nil, sample_frame, nil)

      # First run to stop the listener
      listener_thread = Thread.new do
        socket.start_listening do |_message|
          socket.stop_listening
        end
      end
      listener_thread.join(1)

      # Reset expectation to capture messages from second run
      received = []
      listener_thread = Thread.new do
        socket.start_listening do |message|
          received << message
          socket.stop_listening
        end
      end
      listener_thread.join(1)

      expect(received).to eq([{ id: 0x12345678, extended: false, data: [0xDE, 0xAD, 0xBE, 0xEF] }])
    end
  end

  describe "#stop_listening" do
    it "sets @listening to false" do
      socket.stop_listening
      expect(socket.instance_variable_get(:@listening)).to be false
    end
  end

  describe "#open_can_socket" do
    let(:mock_socket) { instance_double(Socket) }

    before do
      allow(Socket).to receive(:open).and_return(mock_socket)
      allow(mock_socket).to receive(:bind)
      allow(mock_socket).to receive(:setsockopt)
      socket.send(:open_can_socket)
    end

    it "opens a CAN socket with the correct parameters" do
      expect(Socket).to have_received(:open).with(Socket::PF_CAN, Socket::SOCK_RAW, Socket::CAN_RAW)
    end

    it "binds the socket to the interface" do
      expect(mock_socket).to have_received(:bind)
    end

    it "sets the socket options" do
      expect(mock_socket).to have_received(:setsockopt)
    end

    context "when an error occurs" do
      it "rescues the error, logs it, and returns nil" do
        allow(Socket).to receive(:open).and_raise(StandardError.new("Test error"))
        expect(silent_logger).to receive(:error).with(/Error creating CAN socket on interface/)
        result = socket.send(:open_can_socket)
        expect(result).to be_nil
      end
    end
  end

  describe "#receive_message" do
    let(:mock_socket) { instance_double(Socket) }

    it "returns a parsed message hash from the frame" do
      allow(mock_socket).to receive(:recv).and_return(sample_frame)
      message = socket.send(:receive_message, socket: mock_socket)
      expect(message).to eq(id: 0x12345678, extended: false, data: [0xDE, 0xAD, 0xBE, 0xEF])
    end

    it "returns nil if IO::WaitReadable is raised" do
      allow(mock_socket).to receive(:recv).and_raise(IO::WaitReadable)
      expect(socket.send(:receive_message, socket: mock_socket)).to be_nil
    end

    context "when StandardError is raised" do
      it "rescues the error, logs it, and returns nil" do
        allow(mock_socket).to receive(:recv).and_raise(StandardError.new("Test error"))
        expect(silent_logger).to receive(:error).with(/Error receiving CAN message on interface/)
        expect(socket.send(:receive_message, socket: mock_socket)).to be_nil
      end
    end
  end

  describe "#parse_frame" do
    let(:eff_bit)       { 0x80000000 }
    let(:base_id)       { 0x1ABC }
    let(:full_extended) { base_id | eff_bit }
    let(:data_bytes)    { [0xDE, 0xAD, 0xBE, 0xEF] }

    def build_extended_frame(raw_id, data)
      # For big-endian: pack("N") is the same as pack("L>")
      frame_id = [raw_id].pack("N")
      # DLC=4, plus 3 pad
      dlc_and_pad = [data.size, 0, 0, 0].pack("C*")
      # data (4 bytes) + pad to 8 bytes
      payload = data.pack("C*").ljust(8, "\x00")
      frame_id + dlc_and_pad + payload
    end

    it "correctly identifies an extended frame and extracts the ID" do
      raw_frame = build_extended_frame(full_extended, data_bytes)

      parsed = socket.send(:parse_frame, frame: raw_frame)
      expect(parsed).not_to be_nil

      # We expect parse_frame to report extended: true
      expect(parsed[:extended]).to eq(true)

      # The final ID should be the lower 29 bits of raw_id
      # i.e., 0x1ABC
      expect(parsed[:id]).to eq(base_id)

      expect(parsed[:data]).to eq(data_bytes)
    end

    it "parses a raw frame into an id and data" do
      parsed = socket.send(:parse_frame, frame: sample_frame)
      expect(parsed).to eq(id: 0x12345678, extended: false, data: [0xDE, 0xAD, 0xBE, 0xEF])
    end

    context "when an error occurs during parsing" do
      it "rescues the error, logs it, and returns nil" do
        # Force any call to unpack1 on any String to raise an error
        allow_any_instance_of(String).to receive(:unpack1).and_raise(StandardError.new("Test error"))
        expect(silent_logger).to receive(:error).with(/Error parsing CAN frame: Test error/)
        result = socket.send(:parse_frame, frame: sample_frame)
        expect(result).to be_nil
      end
    end
  end

  describe "#matches_filter?" do
    let(:messenger) { described_class.new(interface_name: "can0", logger: silent_logger) }

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
      expect(messenger.send(:matches_filter?, message_id: 0x123, filter: [0x123, 0x124, 0x125])).to be(true)
      expect(messenger.send(:matches_filter?, message_id: 0x126, filter: [0x123, 0x124, 0x125])).to be(false)
    end
  end
end
