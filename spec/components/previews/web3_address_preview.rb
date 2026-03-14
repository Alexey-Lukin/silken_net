# frozen_string_literal: true

# @label Web3 Address
# @display bg_color "#000"
class Web3AddressPreview < Lookbook::Preview
  # @label Valid Ethereum Address
  # @notes Full-length Ethereum address with truncation and copy button.
  def valid_address
    render Views::Shared::Web3::Address.new(address: "0x1234567890abcdef1234567890abcdef12345678")
  end

  # @label Short Address
  # @notes Short address displayed without truncation.
  def short_address
    render Views::Shared::Web3::Address.new(address: "0x1234abcd")
  end

  # @label Nil Address (Fallback)
  # @notes Displays the default NOT_PROVISIONED fallback.
  def nil_address
    render Views::Shared::Web3::Address.new(address: nil)
  end

  # @label Custom Fallback
  # @notes Custom fallback text for unprovisioned wallets.
  def custom_fallback
    render Views::Shared::Web3::Address.new(address: nil, fallback: "AWAITING_GENESIS")
  end

  # @label Interactive
  # @param address text "Ethereum hex address (0x...)"
  # @param fallback text "Fallback text when address is nil"
  def interactive(address: "0xDeadBeef1234567890abcdef1234567890abcdef", fallback: "NOT_PROVISIONED")
    addr = address.presence
    render Views::Shared::Web3::Address.new(address: addr, fallback: fallback)
  end
end
