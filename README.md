# CanMessenger

[![Gem Version](https://badge.fury.io/rb/can_messenger.svg?icon=si%3Arubygems&icon_color=%23e77682&123)](https://badge.fury.io/rb/can_messenger)
[![Build Status](https://github.com/fk1018/can_messenger/actions/workflows/ruby.yml/badge.svg)](https://github.com/fk1018/can_messenger/actions)
[![Test Coverage](https://codecov.io/gh/fk1018/can_messenger/branch/main/graph/badge.svg)](https://codecov.io/gh/fk1018/can_messenger)
![Status](https://img.shields.io/badge/status-stable-green)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](https://opensource.org/licenses/MIT)
![Gem Total Downloads](https://img.shields.io/gem/dt/can_messenger)
![CodeRabbit Pull Request Reviews](https://img.shields.io/coderabbit/prs/github/fk1018/can_messenger?utm_source=oss&utm_medium=github&utm_campaign=fk1018%2Fcan_messenger&labelColor=171717&color=FF570A&link=https%3A%2F%2Fcoderabbit.ai&label=CodeRabbit+Reviews)

`can_messenger` is a Ruby gem that provides an interface for communicating over the CAN bus, allowing users to send and receive CAN messages `via raw SocketCAN sockets`. This gem is designed for developers who need an easy way to interact with CAN-enabled devices on Linux.

## Requirements

- Ruby 3.0 or higher.

## Installation

To install `can_messenger`, add it to your application's Gemfile:

```ruby
gem 'can_messenger'
```

Then execute:

```bash
bundle install
```

Or install it yourself with:

```bash
gem install can_messenger
```

## Usage

### Initializing the Messenger

To create a new instance of `CanMessenger` and start sending messages:

```ruby
require 'can_messenger'

messenger = CanMessenger::Messenger.new(interface_name: 'can0')
```

### Sending CAN Messages

To send a message:

```ruby
messenger.send_can_message(id: 0x123, data: [0xDE, 0xAD, 0xBE, 0xEF])
```

> **Note:** Under the hood, the gem now writes CAN frames to a raw socket instead of calling `cansend`. No external dependencies are required beyond raw-socket permissions.

If you need to send an extended CAN frame (29-bit ID), set extended_id: true. The gem then sets the Extended Frame Format (EFF) bit automatically:

```ruby
messenger.send_can_message(id: 0x123456, data: [0x01, 0x02, 0x03], extended_id: true)
```

If you need to work with **CAN FD** frames (up to 64 data bytes), enable the mode per call or when initializing the messenger:

```ruby
messenger_fd = CanMessenger::Messenger.new(interface_name: 'can0', can_fd: true)
messenger_fd.send_can_message(id: 0x123, data: Array.new(12, 0xFF))
# Or on demand
messenger.send_can_message(id: 0x123, data: Array.new(12, 0xFF), can_fd: true)
```

### Receiving CAN Messages

To listen for incoming messages, set up a listener:

```ruby
messenger.start_listening do |msg|
  puts "Received ID=0x#{msg[:id].to_s(16)}, Extended=#{msg[:extended]}, Data=#{msg[:data]}"
end
```

#### Listening with Filters

The `start_listening` method supports filtering incoming messages based on CAN ID:

- Single CAN ID:

  ```ruby
  messenger.start_listening(filter: 0x123) do |message|
    puts "Received filtered message: #{message}"
  end
  ```

- Range of CAN IDs:

  ```ruby
  messenger.start_listening(filter: 0x100..0x200) do |message|
    puts "Received filtered message: #{message}"
  end
  ```

- Array of CAN IDs:

  ```ruby
  messenger.start_listening(filter: [0x123, 0x456, 0x789]) do |message|
    puts "Received filtered message: #{message}"
  end
  ```

### Working with DBC Files

Parse a DBC file and let the messenger encode and decode messages automatically:

```ruby
dbc = CanMessenger::DBC.load('example.dbc')

# Encode using signal values
messenger.send_dbc_message(dbc: dbc, message_name: 'Example', signals: { Speed: 100 })

# Decode received frames
messenger.start_listening(dbc: dbc) do |msg|
  if msg[:decoded]
    puts "#{msg[:decoded][:name]} => #{msg[:decoded][:signals]}"
  end
end
```

### Stopping the Listener

To stop listening, use:

```ruby
messenger.stop_listening
```

## Important Considerations

Before using `can_messenger`, please note the following:

- **Environment Requirements:**

  - **SocketCAN** must be available on your Linux system.
  - **Permissions:** Working with raw sockets may require elevated privileges or membership in a specific group to open and bind to CAN interfaces without running as root.

- **API Changes (v1.0.0 and later):**

  - **Keyword Arguments:** The Messenger API now requires keyword arguments. For example, when initializing the Messenger:

    ```ruby
    messenger = CanMessenger::Messenger.new(interface_name: 'can0')
    ```

    Similarly, methods like `send_can_message` use named parameters:

    ```ruby
    messenger.send_can_message(id: 0x123, data: [0xDE, 0xAD, 0xBE, 0xEF])
    ```

    If upgrading from an earlier version, update your code accordingly.

  - **Block Requirement for `start_listening`:**  
    The `start_listening` method requires a block. If no block is provided, the method logs an error and exits without processing messages:
    ```ruby
    messenger.start_listening do |message|
      puts "Received: #{message}"
    end
    ```

- **Threading & Socket Management:**

  - **Blocking Behavior:** The gem uses blocking socket calls and continuously listens for messages. Manage the listener’s lifecycle appropriately, especially in multi-threaded environments. Always call `stop_listening` to gracefully shut down the listener.
  - **Resource Cleanup:** The socket is automatically closed when the listening loop terminates. Stop the listener to avoid resource leaks.

- **Logging:**

  - **Default Logger:** If no logger is provided, logs go to standard output. Provide a custom logger if you want more control.

- **CAN Frame Format Assumptions:**
  - By default, the gem uses **big-endian** packing for CAN IDs. If you integrate with a system using little-endian, you may need to adjust or specify an endianness in the code.
  - The gem expects a standard CAN frame layout (16 bytes total, with the first 4 for the ID, followed by 1 byte for DLC, 3 bytes of padding, and up to 8 bytes of data). **CAN FD** frames (up to 64 bytes) are supported when enabled.

## Features

- **Send CAN Messages**: Send CAN messages (up to 8 data bytes, or 64 bytes with CAN FD enabled).
- **Receive CAN Messages**: Continuously listen for messages on a CAN interface.
- **Filtering**: Optional ID filters for incoming messages (single ID, range, or array).
- **Logging**: Logs errors and events for debugging/troubleshooting.
- **DBC Parsing**: Parse DBC files to encode messages by name and decode incoming frames.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test:rspec` to execute the test suite.

## Contributing

Bug reports and pull requests are welcome on GitHub at [https://github.com/fk1018/can_messenger](https://github.com/fk1018/can_messenger).

## License

The gem is available as open-source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Author

Developed by fk1018.
