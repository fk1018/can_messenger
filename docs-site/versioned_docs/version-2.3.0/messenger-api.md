---
sidebar_position: 4
---

# Messenger API

`CanMessenger::Messenger` is the high-level runtime API.

## Constructor

```ruby
CanMessenger::Messenger.new(
  interface_name:,
  logger: nil,
  endianness: :native,
  can_fd: false,
  adapter: CanMessenger::Adapter::Socketcan
)
```

Parameters:

- `interface_name` (required): CAN interface name such as `can0` or `vcan0`.
- `logger`: Defaults to `Logger.new($stdout)` when omitted.
- `endianness`: `:native`, `:little`, or `:big` for CAN ID byte order.
- `can_fd`: Default CAN FD behavior.
- `adapter`: Adapter class or instance implementing the base adapter contract.

## `send_can_message`

```ruby
send_can_message(id:, data:, extended_id: false, can_fd: nil)
```

Behavior:

- Raises `ArgumentError` when required inputs are missing or invalid.
- Uses messenger-level `can_fd` when `can_fd:` is omitted.
- For non-argument runtime errors, logs and returns without raising.

## `send_dbc_message`

```ruby
send_dbc_message(message_name:, signals:, dbc:, extended_id: false, can_fd: nil)
```

Behavior:

- Requires a non-nil `dbc` instance.
- Calls `dbc.encode_can(...)` and then sends the encoded frame.
- Automatically sends DBC messages with the extended CAN flag when the DBC message ID includes the EFF bit.

## `start_listening`

```ruby
start_listening(filter: nil, can_fd: nil, dbc: nil) { |message| ... }
```

Behavior:

- Requires a block. If no block is provided, logs an error and returns.
- Validates `filter:` before opening the socket.
- Loops until `stop_listening` is called.
- Optional `filter` accepts:
  - `Integer`
  - `Range<Integer>`
  - `Array<Integer>`
- Unsupported filter values raise `ArgumentError`.
- Message payload shape from SocketCAN adapter:

```ruby
{
  id: Integer,
  data: Array<Integer>,
  extended: true | false,
  decoded: { name: String, signals: Hash }, # only when dbc decode succeeds
  decode_error: { class: String, message: String } # only when dbc decode raises
}
```

When `dbc:` is provided, extended received frames are mapped back to the DBC message ID form before decode.
If DBC decoding fails, the raw frame is still yielded with `decode_error` attached.

## `stop_listening`

```ruby
stop_listening
```

Sets the internal listening flag to false so the loop exits cleanly.
