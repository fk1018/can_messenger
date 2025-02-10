# frozen_string_literal: true

require_relative "lib/can_messenger/version"

Gem::Specification.new do |spec|
  spec.name          = "can_messenger"
  spec.version       = CanMessenger::VERSION
  spec.authors       = ["fk1018"]
  spec.email         = ["fk1018@users.noreply.github.com"]

  spec.summary       = "A simple Ruby wrapper to read and write CAN bus messages."
  spec.description   = "CanMessenger provides an interface to send and receive messages over the CAN bus, useful for applications requiring CAN communication in Ruby." # rubocop:disable Layout/LineLength
  spec.homepage      = "https://github.com/fk1018/can_messenger"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  # Metadata for RubyGems
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/fk1018/can_messenger"
  spec.metadata["changelog_uri"] = "https://github.com/fk1018/can_messenger/blob/main/CHANGELOG.md"

  # Files to include in the gem package
  spec.files = Dir["lib/**/*", "README.md"]
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a dependency if needed
  # spec.add_dependency "example-gem", "~> 1.0"

  # Development dependencies (optional)
  # spec.add_development_dependency "rspec"       # For testing
  spec.metadata["rubygems_mfa_required"] = "true"
end
