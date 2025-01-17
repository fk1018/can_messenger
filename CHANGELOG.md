## [Unreleased]

### Added

### Changed

### Fixed

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

[0.2.1]: https://github.com/fk1018/can_messenger/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/fk1018/can_messenger/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/fk1018/can_messenger/releases/tag/v0.1.0
