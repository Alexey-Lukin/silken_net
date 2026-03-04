# frozen_string_literal: true

FactoryBot.define do
  factory :blockchain_transaction do
    wallet
    amount { 10.0 }
    token_type { :carbon_coin }
    status { :confirmed }
    to_address { "0x1234567890abcdef1234567890abcdef12345678" }
    tx_hash { SecureRandom.hex(32) }
    notes { "Test minting transaction" }
  end
end
