## [Unreleased]

## [1.4.0] - 2025-07-25

### Added

- `send_dbc_message` helper for encoding and sending messages defined in DBC files.

### Changed

- `send_can_message` now only accepts raw frame parameters.
- DBC parsing code split into helper methods for clarity.

### Fixed

- Correct encoding of negative signal values using two's-complement.

## [1.3.0] - 2025-06-27

### Added

- Optional **CAN FD** support for sending and receiving up to 64-byte frames.

### Changed

- Updated APIs to accept a `can_fd:` flag on initialization and message methods.

### Fixed

- (Nothing since last release.)

## [1.2.1] - 2025-06-05

### Changed

- `send_can_message` now raises `ArgumentError` when data length exceeds eight bytes.
- Updated RBS `initialize` signature to include the `endianness` argument.
- Fixed formatting in README around extended CAN frames.
- Clarified spec helper comment.

### Fixed

- Addressed a listener restart bug allowing `start_listening` to be called again.

## [1.2.0] - 2025-02-28

### Added

- **Explicit extended CAN ID support**.
  - Added an `extended_id: false` parameter to `send_can_message`, which, if set to `true`, sets the Extended Frame Format bit (bit 31) in the CAN ID.
  - Updated `parse_frame` to detect and report `extended: true` when the EFF bit is set in incoming frames.
  - Added corresponding tests for sending and receiving extended CAN frames.

### Changed

- _No breaking changes_, but internal refactoring around how CAN IDs are packed and unpacked.
  - Removed the masking of bit 31 in `unpack_frame_id`, ensuring extended frames are no longer silently treated as standard frames.

### Fixed

- (Nothing since last release.)

## [1.1.0] - 2025-02-10

### Changed

- **Removed dependency on `cansend`**. We now write CAN frames directly via raw sockets.
- Internal refactoring to support raw-socket–based sending without changing the public API.

### Fixed

## [1.0.3] - 2025-02-09

- Revert release.yml

### Fixed

## [1.0.2] - 2025-02-09

- Bugfix release.yml

## [1.0.1] - 2025-02-09

### Changed

- Updated the README to include an **Important Considerations** section that outlines environment requirements, API changes (keyword arguments and block requirement), threading and socket management notes, and logging behavior.
- Made minor documentation clarifications and tweaks to help users avoid common pitfalls.

## [1.0.0] - 2025-02-09

### Changed

- **Breaking Change:** Updated the Messenger API to require keyword arguments (e.g., `interface_name:`) for initialization. Existing code using the old API will need to be updated.
- **Breaking Change:** Updated the send_can_message Method to require keyword arguments (e.g., `id:,data:`) to send messages to the can bus. Existing code using the old API will need to be updated.
- Refactored `start_listening`.
- Enhanced error handling throughout the gem with more detailed logging.
- Updated type signatures (RBS) and documentation to match the new API.
- Refactored tests to reflect the new API and improved error handling.

## [0.2.3] - 2025-02-01

### Changed

- Updated the internal listening loop in `start_listening` to continue iterating on nil (timeout) responses instead of breaking out, improving reliability.
- Suppressed log output during tests by injecting a silent logger.
- Updated the test suite to better handle long-running listening loops and error conditions.

## [0.2.2] - 2024-12-06

### Changed

- Updated README.md to reflect modern debian package install command.

## [0.2.1] - 2024-12-06

### Changed

- Updated `start_listening` RBS signature to include the `filter` parameter, ensuring type definitions match the implementation.

## [0.2.0] - 2024-12-05

### Added

- Filtering support for `start_listening` via a `filter` parameter:
  - Single CAN ID.
  - Range of CAN IDs.
  - Array of CAN IDs.

### Changed

- Refactored `start_listening` to support optional filtering of incoming CAN messages.
- Documentation updates for `start_listening` in README.

## [0.1.0] - 2024-11-10

- Initial release
  [1.3.0]: https://github.com/fk1018/can_messenger/compare/v1.2.1...v1.3.0
  [1.2.1]: https://github.com/fk1018/can_messenger/compare/v1.2.0...v1.2.1
  [1.2.0]: https://github.com/fk1018/can_messenger/compare/v1.1.0...v1.2.0
  [1.1.0]: https://github.com/fk1018/can_messenger/compare/v1.0.3...v1.1.0
  [1.0.3]: https://github.com/fk1018/can_messenger/compare/v1.0.1...v1.0.3
  [1.0.1]: https://github.com/fk1018/can_messenger/compare/v1.0.0...v1.0.1
  [1.0.0]: https://github.com/fk1018/can_messenger/compare/v0.2.3...v1.0.0
  [0.2.3]: https://github.com/fk1018/can_messenger/compare/v0.2.2...v0.2.3
  [0.2.2]: https://github.com/fk1018/can_messenger/compare/v0.2.1...v0.2.2
  [0.2.1]: https://github.com/fk1018/can_messenger/compare/v0.2.0...v0.2.1
  [0.2.0]: https://github.com/fk1018/can_messenger/compare/v0.1.0...v0.2.0
  [0.1.0]: https://github.com/fk1018/can_messenger/releases/tag/v0.1.0
