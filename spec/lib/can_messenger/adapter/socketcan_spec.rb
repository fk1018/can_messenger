# frozen_string_literal: true

require_relative "../../../test_helper"
require "socket"
require "logger"
require "stringio"

RSpec.describe CanMessenger::Adapter::Socketcan do
  before(:all) do
    Socket.const_set(:PF_CAN, 29) unless Socket.const_defined?(:PF_CAN)
    Socket.const_set(:AF_CAN, Socket::PF_CAN) unless Socket.const_defined?(:AF_CAN)
  end

  let(:interface) { "can0" }
  let(:log_output) { StringIO.new }
  let(:silent_logger) { Logger.new(log_output) }
  let(:ifaddr) { instance_double("Socket::Ifaddr", name: interface, ifindex: 7) }
  subject(:adapter) { described_class.new(interface_name: interface, logger: silent_logger) }

  # Helper frame used across tests
  def pack_id(id, endianness)
    endianness == :big ? [id].pack("L>") : [id].pack("V")
  end

  def unpack_id(bytes, endianness)
    endianness == :big ? bytes.unpack1("L>") : bytes.unpack1("V")
  end

  def sample_frame
    "#{pack_id(0x12345678, adapter.endianness)}\x04\x00\x00\x00#{[0xDE, 0xAD, 0xBE, 0xEF].pack("C*")}"
  end

  describe "#open_socket" do
    let(:mock_socket) { instance_double(Socket) }

    before do
      allow(Socket).to receive(:open).and_return(mock_socket)
      allow(Socket).to receive(:getifaddrs).and_return([ifaddr])
      allow(mock_socket).to receive(:bind)
      allow(mock_socket).to receive(:setsockopt)
      allow(mock_socket).to receive(:closed?).and_return(false)
      allow(mock_socket).to receive(:close)
    end

    it "opens and configures a CAN socket without Ruby SocketCAN helpers" do
      hide_const("Socket::CAN_RAW") if Socket.const_defined?(:CAN_RAW)
      hide_const("Socket::SOL_CAN_RAW") if Socket.const_defined?(:SOL_CAN_RAW)
      if Socket.respond_to?(:pack_sockaddr_can)
        allow(Socket).to receive(:pack_sockaddr_can).and_raise("should not be called")
      end

      adapter.open_socket
      expect(Socket).to have_received(:open).with(Socket::PF_CAN, Socket::SOCK_RAW, described_class::CAN_RAW)
      expect(mock_socket).to have_received(:bind).with(adapter.send(:build_sockaddr_can, 7))
      expect(mock_socket).to have_received(:setsockopt)
    end

    it "sets CAN_RAW_FD_FRAMES when can_fd is true" do
      allow(mock_socket).to receive(:setsockopt)
      adapter.open_socket(can_fd: true)
      expect(mock_socket).to have_received(:setsockopt).with(
        described_class::SOL_CAN_RAW,
        described_class::CAN_RAW_FD_FRAMES,
        1
      )
    end

    it "falls back to sysfs when getifaddrs does not find the interface" do
      allow(Socket).to receive(:getifaddrs).and_return([])
      allow(File).to receive(:file?).and_call_original
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:file?).with("/sys/class/net/#{interface}/ifindex").and_return(true)
      allow(File).to receive(:read).with("/sys/class/net/#{interface}/ifindex").and_return("12\n")

      adapter.open_socket

      expect(mock_socket).to have_received(:bind).with(adapter.send(:build_sockaddr_can, 12))
    end

    it "logs and returns nil when the interface is unknown" do
      allow(Socket).to receive(:getifaddrs).and_return([])
      allow(File).to receive(:file?).and_call_original
      allow(File).to receive(:file?).with("/sys/class/net/#{interface}/ifindex").and_return(false)

      expect(silent_logger).to receive(:error).with(/Unknown CAN interface #{interface}/)
      expect(adapter.open_socket).to be_nil
      expect(mock_socket).to have_received(:close)
    end

    it "logs and returns nil on error" do
      allow(Socket).to receive(:open).and_raise(StandardError.new("boom"))
      expect(silent_logger).to receive(:error).with(/Error creating CAN socket/)
      expect(adapter.open_socket).to be_nil
    end
  end

  describe "Linux compatibility helpers" do
    it "builds a 24-byte sockaddr_can with the expected layout" do
      sockaddr = adapter.send(:build_sockaddr_can, 7)

      expect(sockaddr.bytesize).to eq(described_class::SOCKADDR_CAN_SIZE)
      expect(sockaddr[0, 2]).to eq([Socket::AF_CAN].pack("S!"))
      expect(sockaddr[2, 2]).to eq("\x00\x00")
      expect(sockaddr[4, 4]).to eq([7].pack("i!"))
      expect(sockaddr[8, 16]).to eq("\x00" * 16)
    end

    it "returns nil when getifaddrs raises a system error" do
      allow(Socket).to receive(:getifaddrs).and_raise(Errno::ENOENT)

      expect(adapter.send(:interface_index_from_ifaddrs)).to be_nil
    end

    it "returns nil when sysfs ifindex is not an integer" do
      allow(File).to receive(:file?).and_call_original
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:file?).with("/sys/class/net/#{interface}/ifindex").and_return(true)
      allow(File).to receive(:read).with("/sys/class/net/#{interface}/ifindex").and_return("invalid\n")

      expect(adapter.send(:interface_index_from_sysfs)).to be_nil
    end

    it "raises when sockaddr_can size does not match the expected struct size" do
      stub_const("#{described_class}::SOCKADDR_CAN_SIZE", 23)

      expect do
        adapter.send(:build_sockaddr_can, 7)
      end.to raise_error(RuntimeError, /sockaddr_can must be 23 bytes, got 24/)
    end
  end

  describe "#build_can_frame" do
    it "defaults to native endianness" do
      expect(adapter.endianness).to eq(described_class.native_endianness)
    end

    it "packs extended IDs little-endian when endianness is :little" do
      le = described_class.new(interface_name: interface, logger: silent_logger, endianness: :little)
      frame = le.build_can_frame(id: 0x12345678, data: [], extended_id: true)
      expect(frame[0..3]).to eq([0x78, 0x56, 0x34, 0x92].pack("C*"))
    end

    it "sets the extended ID bit" do
      frame = adapter.build_can_frame(id: 0x1ABC, data: [], extended_id: true)
      raw_id = unpack_id(frame[0..3], adapter.endianness)
      expect(raw_id & 0x80000000).not_to be_zero
    end

    it "raises error for a negative CAN ID" do
      expect { adapter.build_can_frame(id: -1, data: []) }.to raise_error(ArgumentError, /cannot be negative/)
    end

    it "raises error for a non-integer CAN ID" do
      expect { adapter.build_can_frame(id: "123", data: []) }.to raise_error(ArgumentError, /must be an Integer/)
    end

    it "raises error for a standard CAN ID above 0x7FF" do
      expect { adapter.build_can_frame(id: 0x800, data: []) }.to raise_error(ArgumentError, /0x7FF/)
    end

    it "raises error for an extended CAN ID above 0x1FFFFFFF" do
      expect do
        adapter.build_can_frame(id: 0x20000000, data: [], extended_id: true)
      end.to raise_error(ArgumentError, /0x1FFFFFFF/)
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

    it "keeps a valid standard CAN ID unchanged" do
      frame = adapter.build_can_frame(id: 0x7FF, data: [])
      raw_id = unpack_id(frame[0..3], adapter.endianness)
      expect(raw_id).to eq(0x7FF)
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
      frame = pack_id(eff, adapter.endianness) + [4, 0, 0, 0].pack("C*") + [0, 0, 0, 0].pack("C*")
      parsed = adapter.parse_frame(frame: frame)
      expect(parsed[:extended]).to be true
      expect(parsed[:id]).to eq(0x1ABC)
    end

    it "parses CAN FD frame" do
      data = Array.new(64) { |i| i }
      frame = pack_id(0x123, adapter.endianness) + [data.size, 0, 0, 0].pack("C*") + data.pack("C*")
      parsed = adapter.parse_frame(frame: frame, can_fd: true)
      expect(parsed).to eq(id: 0x123, data: data, extended: false)
    end

    it "returns nil for invalid frame" do
      expect(adapter.parse_frame(frame: "\x00" * 4)).to be_nil
    end

    it "logs errors and returns nil" do
      allow(adapter).to receive(:unpack_frame_id).and_raise(StandardError.new("boom"))
      expect(silent_logger).to receive(:error).with(/Error parsing CAN frame/)
      expect(adapter.parse_frame(frame: sample_frame)).to be_nil
    end
  end
end
