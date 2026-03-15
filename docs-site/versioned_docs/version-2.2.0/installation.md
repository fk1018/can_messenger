---
sidebar_position: 2
---

# Installation

## Requirements

- Linux with SocketCAN support.
- Ruby `>= 4.0.1`.
- Permission to open raw sockets (root, `CAP_NET_RAW`, or equivalent setup).

## Install the Gem

Add to your `Gemfile`:

```ruby
gem 'can_messenger'
```

Then install:

```bash
bundle install
```

Or install directly:

```bash
gem install can_messenger
```

RubyGems package page: [can_messenger on RubyGems](https://rubygems.org/gems/can_messenger)

## Prepare a Test CAN Interface (virtual)

For local testing without physical hardware:

```bash
sudo modprobe vcan
sudo ip link add dev vcan0 type vcan
sudo ip link set up vcan0
```

Verify:

```bash
ip -details link show vcan0
```

Then use `interface_name: 'vcan0'` in examples.

## Prepare a Physical CAN Interface (example)

```bash
sudo ip link set can0 down
sudo ip link set can0 up type can bitrate 500000
```

Adjust bitrate/settings to your network requirements.
