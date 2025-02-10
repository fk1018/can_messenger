# spec/can_messenger/version_spec.rb
# frozen_string_literal: true

require "test_helper"

RSpec.describe CanMessenger do
  it "has a version number" do
    expect(CanMessenger::VERSION).not_to be_nil
  end

  it "matches the expected version format" do
    expect(CanMessenger::VERSION).to match(/^\d+\.\d+\.\d+$/)
  end
end
