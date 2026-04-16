---
sidebar_position: 3
---

# Quickstart

## Create a Messenger

```ruby
require 'can_messenger'

messenger = CanMessenger::Messenger.new(interface_name: 'can0')
```

## Send a Standard CAN Frame

```ruby
messenger.send_can_message(id: 0x123, data: [0xDE, 0xAD, 0xBE, 0xEF])
```

## Send an Extended-ID Frame

```ruby
messenger.send_can_message(
  id: 0x123456,
  data: [0x01, 0x02, 0x03],
  extended_id: true
)
```

## Send CAN FD

Enable globally on the messenger:

```ruby
fd_messenger = CanMessenger::Messenger.new(interface_name: 'can0', can_fd: true)
fd_messenger.send_can_message(id: 0x200, data: Array.new(12, 0xAA))
```

Or per call:

```ruby
messenger.send_can_message(id: 0x200, data: Array.new(12, 0xAA), can_fd: true)
```

## Listen for Frames

```ruby
listener = Thread.new do
  messenger.start_listening do |msg|
    puts "id=0x#{msg[:id].to_s(16)} extended=#{msg[:extended]} data=#{msg[:data].inspect}"
  end
end

sleep 2
messenger.stop_listening
listener.join
```

## Apply ID Filters

```ruby
# One ID
messenger.start_listening(filter: 0x123) { |msg| p msg }

# Range
messenger.start_listening(filter: 0x100..0x1FF) { |msg| p msg }

# Explicit list
messenger.start_listening(filter: [0x120, 0x121, 0x220]) { |msg| p msg }
```

## DBC-assisted Send/Receive

```ruby
dbc = CanMessenger::DBC.load('vehicle.dbc')

messenger.send_dbc_message(
  dbc: dbc,
  message_name: 'EngineData',
  signals: { RPM: 2200, Temp: 84 }
)

messenger.start_listening(dbc: dbc) do |msg|
  p msg[:decoded] if msg[:decoded]
end
```

If `EngineData` is defined in the DBC with an extended CAN ID, `send_dbc_message` automatically sends it as an extended frame and the receive path decodes the extended frame back through the same DBC message definition.
