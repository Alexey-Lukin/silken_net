# frozen_string_literal: true

FactoryBot.define do
  factory :ethereum_anchor do
    state_root { SecureRandom.hex(32) }
    total_scc { rand(100.0..100_000.0).round(2) }
    chain_hash { SecureRandom.hex(16) }
    anchored_at { Time.current }
    status { :pending }

    trait :sent do
      status { :sent }
      tx_hash { "0x#{SecureRandom.hex(32)}" }
    end

    trait :confirmed do
      status { :confirmed }
      tx_hash { "0x#{SecureRandom.hex(32)}" }
      block_number { rand(10_000_000..20_000_000) }
      gas_used { rand(21_000..100_000) }
    end

    trait :failed do
      status { :failed }
      error_message { "Transaction reverted" }
    end
  end
end
