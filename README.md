# CanMessenger

[![Gem Version](https://badge.fury.io/rb/can_messenger.svg?icon=si%3Arubygems&icon_color=%23e77682)](https://badge.fury.io/rb/can_messenger)
[![Build Status](https://github.com/fk1018/can_messenger/actions/workflows/ruby.yml/badge.svg)](https://github.com/fk1018/can_messenger/actions)
[![Test Coverage](https://codecov.io/gh/fk1018/can_messenger/branch/main/graph/badge.svg)](https://codecov.io/gh/fk1018/can_messenger)
![Status](https://img.shields.io/badge/status-stable-green)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](https://opensource.org/licenses/MIT)
![Gem Total Downloads](https://img.shields.io/gem/dt/can_messenger)

`can_messenger` is a Ruby gem that provides an interface for communicating over the CAN bus, allowing users to send and receive CAN messages. This gem is designed for developers who need an easy way to interact with CAN-enabled devices.

## Installation

This gem relies on `cansend` from the `can-utils` package, which is typically available on Linux-based systems. Make sure to install `can-utils` before using `can_messenger`:

```bash
sudo apt install can-utils
```

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

### Receiving CAN Messages

To listen for incoming messages, set up a listener:

```ruby
messenger.start_listening do |message|
    puts "Received: ID=#{message[:id]}, Data=#{message[:data]}"
end
```

#### Listening with Filters

The `start_listening` method supports filtering incoming messages based on CAN ID:

Single CAN ID:

```ruby
messenger.start_listening(filter: 0x123) do |message|
  puts "Received filtered message: #{message}"
end
```

Range of CAN IDs:

```ruby
messenger.start_listening(filter: 0x100..0x200) do |message|
  puts "Received filtered message: #{message}"
end

```

Array of CAN IDs:

```ruby
messenger.start_listening(filter: [0x123, 0x456, 0x789]) do |message|
  puts "Received filtered message: #{message}"
end

```

### Stopping the Listener

To stop listening, use:

```ruby
messenger.stop_listening
```

## Features

- **Send CAN Messages**: Send CAN messages with a specified ID.
- **Receive CAN Messages**: Continuously listen for messages on a CAN interface.
- **Logging**: Logs errors and events for debugging and troubleshooting.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test:rspec` to run the tests.

## Contributing

Bug reports and pull requests are welcome on GitHub at [https://github.com/fk1018/can_messenger](https://github.com/fk1018/can_messenger).

## License

The gem is available as open-source under the terms of the MIT License.

## Author

Developed by fk1018.
