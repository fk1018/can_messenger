# frozen_string_literal: true

require_relative "../../../test_helper"
require "logger"

RSpec.describe CanMessenger::Adapter::Base do
  subject(:adapter) { described_class.new(interface_name: "can0", logger: Logger.new(nil)) }

  it "raises NotImplementedError for open_socket" do
    expect { adapter.open_socket }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for build_can_frame" do
    expect { adapter.build_can_frame(id: 1, data: []) }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for receive_message" do
    expect { adapter.receive_message(socket: nil) }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for parse_frame" do
    expect { adapter.parse_frame(frame: "") }.to raise_error(NotImplementedError)
  end
end
