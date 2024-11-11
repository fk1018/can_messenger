# CanMessenger

`can_messenger` is a Ruby gem that provides an interface for communicating over the CAN bus, allowing users to send and receive CAN messages. This gem is designed for developers who need an easy way to interact with CAN-enabled devices.

## Installation

This gem relies on `cansend` from the `can-utils` package, which is typically available on Linux-based systems. Make sure to install `can-utils` before using `can_messenger`:

```bash
sudo apt-get install can-utils
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

messenger = CanMessenger::Messenger.new('can0')
```

### Sending CAN Messages

To send a message:

```ruby
messenger.send_can_message(0x123, [0xDE, 0xAD, 0xBE, 0xEF])
```

### Receiving CAN Messages

To listen for incoming messages, set up a listener:

```ruby
messenger.start_listening do |message|
puts "Received: ID=#{message[:id]}, Data=#{message[:data]}"
end
```

### Stopping the Listener

To stop listening, use:

```ruby
messenger.stop_listening
```

## Features

- **Send CAN Messages**: Send data to specified CAN IDs.
- **Receive CAN Messages**: Continuously listen for messages on a CAN interface.
- **Logging**: Logs errors and events for debugging and troubleshooting.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests.

To install this gem onto your local machine, run:

```bash
bundle exec rake install
```

## Contributing

Bug reports and pull requests are welcome on GitHub at [https://github.com/fk1018/can_messenger](https://github.com/fk1018/can_messenger).

## License

The gem is available as open-source under the terms of the MIT License.

## Author

Developed by Fredrick Khoury.
