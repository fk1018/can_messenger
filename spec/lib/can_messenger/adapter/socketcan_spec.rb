# frozen_string_literal: true

require_relative "../../../test_helper"
require "socket"
require "logger"
require "stringio"

RSpec.describe CanMessenger::Adapter::Socketcan do
  before(:all) do
    Socket.const_set(:CAN_RAW, 1) unless Socket.const_defined?(:CAN_RAW)
    Socket.const_set(:PF_CAN, 29) unless Socket.const_defined?(:PF_CAN)
    Socket.const_set(:CAN_RAW_FD_FRAMES, 1) unless Socket.const_defined?(:CAN_RAW_FD_FRAMES)
    Socket.const_set(:SOL_CAN_RAW, 101) unless Socket.const_defined?(:SOL_CAN_RAW)

    unless Socket.respond_to?(:pack_sockaddr_can)
      def Socket.pack_sockaddr_can(_interface)
        "\x00" * 16
      end
    end
  end

  let(:interface) { "can0" }
  let(:log_output) { StringIO.new }
  let(:silent_logger) { Logger.new(log_output) }
  subject(:adapter) { described_class.new(interface_name: interface, logger: silent_logger) }

  # Helper frame used across tests
  def sample_frame
    "#{[0x12345678].pack("L>")}\x04\x00\x00\x00#{[0xDE, 0xAD, 0xBE, 0xEF].pack("C*")}"
  end

  describe "#open_socket" do
    let(:mock_socket) { instance_double(Socket) }

    before do
      allow(Socket).to receive(:open).and_return(mock_socket)
      allow(mock_socket).to receive(:bind)
      allow(mock_socket).to receive(:setsockopt)
    end

    it "opens and configures a CAN socket" do
      adapter.open_socket
      expect(Socket).to have_received(:open).with(Socket::PF_CAN, Socket::SOCK_RAW, Socket::CAN_RAW)
      expect(mock_socket).to have_received(:bind)
      expect(mock_socket).to have_received(:setsockopt)
    end

    it "sets CAN_RAW_FD_FRAMES when can_fd is true" do
      allow(mock_socket).to receive(:setsockopt)
      adapter.open_socket(can_fd: true)
      expect(mock_socket).to have_received(:setsockopt).with(Socket::SOL_CAN_RAW, Socket::CAN_RAW_FD_FRAMES, 1)
    end

    it "logs and returns nil on error" do
      allow(Socket).to receive(:open).and_raise(StandardError.new("boom"))
      expect(silent_logger).to receive(:error).with(/Error creating CAN socket/)
      expect(adapter.open_socket).to be_nil
    end
  end

  describe "#build_can_frame" do
    it "packs ID little-endian when endianness is :little" do
      le = described_class.new(interface_name: interface, logger: silent_logger, endianness: :little)
      frame = le.build_can_frame(id: 0x12345678, data: [])
      expect(frame[0..3]).to eq([0x78, 0x56, 0x34, 0x12].pack("C*"))
    end

    it "sets the extended ID bit" do
      frame = adapter.build_can_frame(id: 0x1ABC, data: [], extended_id: true)
      expect(frame[0..3].unpack1("L>") & 0x80000000).not_to be_zero
    end

    it "raises error when data length exceeds 8 bytes" do
      expect { adapter.build_can_frame(id: 0x1, data: Array.new(9, 0xFF)) }.to raise_error(ArgumentError)
    end

    it "raises error when CAN FD data exceeds 64 bytes" do
      expect { adapter.build_can_frame(id: 0x1, data: Array.new(65, 0xFF), can_fd: true) }.to raise_error(ArgumentError)
    end

    it "builds CAN FD frame" do
      data = Array.new(64, 0xAA)
      frame = adapter.build_can_frame(id: 0x123, data: data, can_fd: true)
      expect(frame.bytesize).to eq(72)
    end
  end

  describe "#receive_message" do
    let(:mock_socket) { instance_double(Socket) }

    it "returns parsed message" do
      allow(mock_socket).to receive(:recv).and_return(sample_frame)
      msg = adapter.receive_message(socket: mock_socket)
      expect(msg).to eq(id: 0x12345678, data: [0xDE, 0xAD, 0xBE, 0xEF], extended: false)
    end

    it "handles IO::WaitReadable" do
      allow(mock_socket).to receive(:recv).and_raise(IO::WaitReadable)
      expect(adapter.receive_message(socket: mock_socket)).to be_nil
    end

    it "logs StandardError" do
      allow(mock_socket).to receive(:recv).and_raise(StandardError.new("boom"))
      expect(silent_logger).to receive(:error).with(/Error receiving CAN message/)
      expect(adapter.receive_message(socket: mock_socket)).to be_nil
    end

    it "requests CANFD_FRAME_SIZE when can_fd true" do
      allow(mock_socket).to receive(:recv).and_return(sample_frame)
      adapter.receive_message(socket: mock_socket, can_fd: true)
      expect(mock_socket).to have_received(:recv).with(described_class::CANFD_FRAME_SIZE)
    end
  end

  describe "#parse_frame" do
    it "identifies extended frames" do
      eff = 0x80000000 | 0x1ABC
      frame = [eff].pack("L>") + [4, 0, 0, 0].pack("C*") + [0, 0, 0, 0].pack("C*")
      parsed = adapter.parse_frame(frame: frame)
      expect(parsed[:extended]).to be true
      expect(parsed[:id]).to eq(0x1ABC)
    end

    it "parses CAN FD frame" do
      data = Array.new(64) { |i| i }
      frame = [0x123].pack("L>") + [data.size, 0, 0, 0].pack("C*") + data.pack("C*")
      parsed = adapter.parse_frame(frame: frame, can_fd: true)
      expect(parsed).to eq(id: 0x123, data: data, extended: false)
    end

    it "returns nil for invalid frame" do
      expect(adapter.parse_frame(frame: "\x00" * 4)).to be_nil
    end

    it "logs errors and returns nil" do
      allow_any_instance_of(String).to receive(:unpack1).and_raise(StandardError.new("boom"))
      expect(silent_logger).to receive(:error).with(/Error parsing CAN frame/)
      expect(adapter.parse_frame(frame: sample_frame)).to be_nil
    end
  end
end
