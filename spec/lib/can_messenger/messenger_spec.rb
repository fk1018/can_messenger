# messenger_spec.rb
# frozen_string_literal: true

require "test_helper"
require "socket"
require "logger"

RSpec.describe CanMessenger::Messenger do # rubocop:disable Metrics/BlockLength
  before(:all) do
    unless Socket.const_defined?(:CAN_RAW)
      Socket.const_set(:CAN_RAW, 1)
      Socket.const_set(:PF_CAN, 29)
    end

    # Mock pack_sockaddr_can if it's not available
    unless Socket.respond_to?(:pack_sockaddr_can)
      def Socket.pack_sockaddr_can(_interface)
        "\x00" * 16 # Simulate a 16-byte packed sockaddr structure
      end
    end
  end

  let(:interface) { "can0" }
  let(:socket) { described_class.new(interface) }

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
      expect(socket.instance_variable_get(:@can_interface)).to eq(interface)
    end

    it "initializes listening as true" do
      expect(socket.instance_variable_get(:@listening)).to be true
    end
  end

  describe "#send_can_message" do
    let(:command) { "cansend #{interface} #{format("%03X", 0x123)}#DEADBEEF" }

    it "sends the message using the correct command" do
      expect(socket.send_can_message(0x123, [0xDE, 0xAD, 0xBE, 0xEF])).to be true
      expect(socket).to have_received(:system).with(command)
    end
  end

  describe "#start_listening" do # rubocop:disable Metrics/BlockLength
    let(:mock_socket) { instance_double(Socket) }

    before do
      allow(socket).to receive(:create_socket).and_return(mock_socket)
      allow(mock_socket).to receive(:close)
    end

    def capture_received_messages
      received_messages = []
      socket.start_listening do |message|
        received_messages << message
        socket.stop_listening # Explicitly stop after one message to prevent infinite loop
      end
      received_messages
    end

    it "yields received messages to the block" do
      allow(mock_socket).to receive(:recv).and_return(sample_frame, nil)
      expect(capture_received_messages).to eq([{ id: 0x12345678, data: [0xDE, 0xAD, 0xBE, 0xEF] }])
    end

    it "closes the socket after listening" do
      allow(mock_socket).to receive(:recv).and_return(nil)
      socket.start_listening { socket.stop_listening }
      expect(mock_socket).to have_received(:close)
    end

    it "handles IO::WaitReadable gracefully" do
      allow(mock_socket).to receive(:recv).and_raise(IO::WaitReadable)
      expect { socket.start_listening { socket.stop_listening } }.not_to raise_error
    end

    it "handles StandardError gracefully" do
      allow(mock_socket).to receive(:recv).and_raise(StandardError)
      expect { socket.start_listening { socket.stop_listening } }.not_to raise_error
    end
  end

  describe "#stop_listening" do
    it "sets @listening to false" do
      socket.stop_listening
      expect(socket.instance_variable_get(:@listening)).to be false
    end
  end

  describe "#create_socket" do
    let(:mock_socket) { instance_double(Socket) }

    before do
      allow(Socket).to receive(:open).and_return(mock_socket)
      allow(mock_socket).to receive(:bind)
      allow(mock_socket).to receive(:setsockopt)
      socket.send(:create_socket)
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
  end

  describe "#receive_message" do
    let(:mock_socket) { instance_double(Socket) }

    it "returns a parsed message hash from the frame" do
      allow(mock_socket).to receive(:recv).and_return(sample_frame)
      message = socket.send(:receive_message, mock_socket)
      expect(message).to eq(id: 0x12345678, data: [0xDE, 0xAD, 0xBE, 0xEF])
    end

    it "returns nil if IO::WaitReadable is raised" do
      allow(mock_socket).to receive(:recv).and_raise(IO::WaitReadable)
      expect(socket.send(:receive_message, mock_socket)).to be_nil
    end
  end

  describe "#parse_frame" do
    it "parses a raw frame into an id and data" do
      parsed = socket.send(:parse_frame, sample_frame)
      expect(parsed).to eq(id: 0x12345678, data: [0xDE, 0xAD, 0xBE, 0xEF])
    end
  end
end
