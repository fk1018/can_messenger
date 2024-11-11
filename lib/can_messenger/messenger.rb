# lib/can_messenger/messenger.rb
# frozen_string_literal: true

require "socket"
require "logger"

module CanMessenger
  # Messenger
  #
  # This class provides an interface to send and receive CAN bus messages.
  # It supports sending messages with specific CAN IDs and listening for incoming messages.
  #
  # @example
  #   socket = CanMessenger::Messenger.new('can0')
  #   socket.send_can_message(0x123, [0xDE, 0xAD, 0xBE, 0xEF])
  #   socket.start_listening do |message|
  #     puts "Received: ID=#{message[:id]}, Data=#{message[:data].map { |b| '0x%02X' % b }}"
  #   end
  class Messenger
    # Initializes a new Messenger instance.
    #
    # @param [String] can_interface The CAN interface to use (e.g., 'can0').
    # @param [Logger] logger Optional logger for error handling and debug information.
    def initialize(can_interface, logger = nil)
      @can_interface = can_interface
      @logger = logger || Logger.new($stdout)
      @listening = true # Control flag for listening loop
    end

    # Sends a CAN message using the `cansend` command.
    #
    # @param [Integer] id The CAN ID of the message.
    # @param [Array<Integer>] data The data bytes of the CAN message.
    # @return [void]
    def send_can_message(id, data)
      hex_id = format("%03X", id)
      hex_data = data.map { |byte| format("%02X", byte) }.join
      command = "cansend #{@can_interface} #{hex_id}##{hex_data}"
      system(command)
    rescue StandardError => e
      @logger.error("Error sending CAN message (ID: #{id}): #{e}")
    end

    # Continuously listens for CAN messages on the specified interface.
    #
    # Yields each message as a hash with keys :id and :data.
    # @yield [Hash] Each received message in the format { id: Integer, data: Array<Integer> }.
    # @return [void]
    def start_listening
      @logger.info("Started listening on #{@can_interface}")
      socket = create_socket
      while @listening
        message = receive_message(socket)
        break unless message # Exit loop if no message

        yield(message)
      end
    ensure
      socket&.close
    end

    # Stops the listening loop by setting @listening to false.
    #
    # This method can be called from an external thread or signal handler.
    # @return [void]
    def stop_listening
      @listening = false
      @logger.info("Stopped listening on #{@can_interface}")
    end

    private

    # Creates and configures a CAN socket.
    #
    # @return [Socket] The configured CAN socket.
    def create_socket
      socket = Socket.open(Socket::PF_CAN, Socket::SOCK_RAW, Socket::CAN_RAW)
      socket.bind(Socket.pack_sockaddr_can(@can_interface))
      socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, [1, 0].pack("l_2"))
      socket
    rescue StandardError => e
      @logger.error("Error creating CAN socket on interface #{@can_interface}: #{e}")
    end

    # Receives a CAN message from the socket and parses it.
    #
    # @param [Socket] socket The CAN socket to read from.
    # @return [Hash, nil] Parsed message in the format { id: Integer, data: Array<Integer> },
    # or nil if no message is received or an error occurs.
    def receive_message(socket)
      frame = socket.recv(16)
      return nil if frame.nil? || frame.size < 8

      parse_frame(frame)
    rescue IO::WaitReadable
      nil
    rescue StandardError => e
      @logger.error("Error receiving CAN message on interface #{@can_interface}: #{e}")
      nil
    end

    # Parses a raw CAN frame into a message hash.
    #
    # @param [String] frame The raw CAN frame.
    # @return [Hash, nil] Parsed message with :id and :data keys, or nil if the frame is incomplete.
    def parse_frame(frame)
      return nil unless frame && frame.size >= 8

      id = frame[0..3].unpack1("L>") & 0x1FFFFFFF
      data_length = frame[4].ord & 0x0F
      data = (frame[8, data_length].unpack("C*") if frame.size >= 8 + data_length)

      { id: id, data: data }
    rescue StandardError => e
      @logger.error("Error parsing CAN frame: #{e}")
      nil
    end
  end
end
