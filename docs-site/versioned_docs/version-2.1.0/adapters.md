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

- `open_socket(can_fd: false)`
- `build_can_frame(id:, data:, extended_id: false, can_fd: false)`
- `receive_message(socket:, can_fd: false)`
- `parse_frame(frame:, can_fd: false)`

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
