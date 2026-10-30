# frozen_string_literal: true

module CanMessenger
  # Shared CAN identifier masks and frame flags.
  #
  # SocketCAN stores frame flags above the 29 identifier bits. DBC message IDs
  # also use bit 31 to mark extended frames, so the same flag is used when
  # translating between DBC definitions and received frames.
  module Constants
    # Keeps only the 29 identifier bits and removes the frame flags.
    CAN_ID_MASK = 0x1FFFFFFF
    # Bit 31 selects the extended frame format with a 29-bit identifier.
    EXTENDED_ID_FLAG = 0x80000000
    # Bit 30 marks a remote request for data, which carries no signal payload.
    REMOTE_TRANSMISSION_REQUEST_FLAG = 0x40000000
    # Largest valid extended identifier before any frame flags are added.
    MAX_EXTENDED_ID = 0x1FFFFFFF
  end
end
