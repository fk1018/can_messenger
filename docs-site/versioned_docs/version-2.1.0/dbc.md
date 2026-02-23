---
sidebar_position: 5
---

# DBC Guide

`CanMessenger::DBC` parses DBC text and maps signal values to raw CAN bytes.

## Load a DBC File

```ruby
dbc = CanMessenger::DBC.load('example.dbc')
```

You can also parse inline content:

```ruby
dbc = CanMessenger::DBC.new(File.read('example.dbc'))
```

## Supported DBC Elements

Current parser support is intentionally narrow and focused:

- `BO_` message definitions.
- `SG_` signal definitions in the common `start|length@endian+/- (factor,offset)` pattern.
- Skips `BO_TX_BU_` lines.

If your DBC uses advanced constructs (for example multiplexing or uncommon syntax variants), validate with tests before relying on runtime behavior.

## Encode by Message Name

```ruby
frame = dbc.encode_can('Example', Speed: 42)
# => { id: 256, data: [42, ...] }
```

Validation performed during encoding includes:

- Unknown message name rejection.
- Signed/unsigned range checks.
- Signal bit-bound checks against message DLC.

## Decode by CAN ID

```ruby
decoded = dbc.decode_can(frame[:id], frame[:data])
# => { name: 'Example', signals: { Speed: 42.0 } }
```

Returns `nil` if no message with matching CAN ID is found.

## Big-endian and Little-endian Signals

- `@1` is treated as little-endian.
- `@0` is treated as big-endian (Motorola/sawtooth indexing).

`2.1.0` includes corrected multi-byte big-endian bit mapping and stricter unsigned overflow checks.
