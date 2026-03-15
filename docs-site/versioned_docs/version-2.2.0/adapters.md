---
sidebar_position: 6
---

# Adapters

`Messenger` delegates low-level frame I/O to an adapter.

## Default Adapter

By default, `Messenger` uses `CanMessenger::Adapter::Socketcan`, which:

- Opens Linux raw CAN sockets.
- Builds/parses classic CAN and CAN FD frame layouts.
- Detects and exposes `extended` frame flag.

## Adapter Contract

Custom adapters should subclass `CanMessenger::Adapter::Base` and implement:

- `open_socket(can_fd: nil)`
- `build_can_frame(id:, data:, extended_id: false, can_fd: nil)`
- `receive_message(socket:, can_fd: nil)`
- `parse_frame(frame:, can_fd: nil)`

`Socketcan#parse_frame` additionally supports `can_fd: nil` as an auto-detect
mode when parsing raw frames directly:

- `nil`: infer CAN FD from frame size (`>= CANFD_FRAME_SIZE`).
- `false`: force classic CAN parse.
- `true`: force CAN FD parse.

For custom adapters, keep the base signature compatible, and if you expose
direct frame parsing outside the listener path, consider supporting a similar
auto-detect sentinel.

## Injecting an Adapter

You can pass either a class or an already-built instance:

```ruby
# Class injection
messenger = CanMessenger::Messenger.new(
  interface_name: 'can0',
  adapter: MyAdapterClass
)

# Instance injection
adapter = MyAdapterClass.new(interface_name: 'can0', logger: Logger.new($stdout), endianness: :native)
messenger = CanMessenger::Messenger.new(interface_name: 'can0', adapter: adapter)
```

When a class is passed, `Messenger` initializes it with `interface_name`, `logger`, and `endianness`.
