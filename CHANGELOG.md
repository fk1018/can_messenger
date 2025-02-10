## [Unreleased]

### Added

### Changed

### Fixed

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

[1.0.0]: https://github.com/fk1018/can_messenger/compare/v0.2.3...v1.0.0
[0.2.3]: https://github.com/fk1018/can_messenger/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/fk1018/can_messenger/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/fk1018/can_messenger/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/fk1018/can_messenger/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/fk1018/can_messenger/releases/tag/v0.1.0
