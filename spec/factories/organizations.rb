# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

FactoryBot.define do
  factory :organization do
    sequence(:name) { |n| "Test Organization #{n}-#{SecureRandom.hex(4)}" }
    sequence(:billing_email) { |n| "billing#{n}@example.org" }
    # [TEST.11] Адреса — unique і в БД, і у валідації. 🔴 Регістр несучий:
    # `EthAddressValidatable` пропускає всю-однорегістрову адресу як
    # unchecksummed, але МІШАНИЙ регістр звіряє з EIP-55 — тобто випадковий
    # upcase тут завалив би фабричний дефолт майже завжди. `SecureRandom.hex`
    # дає lowercase, і саме тому має лишитись lowercase.
    sequence(:crypto_public_address) { |n| "0x#{format('%08x', n)}#{SecureRandom.hex(16)}" }

    trait :forest_fund do
      name { "Cherkasy Forest Fund" }
      billing_email { "billing@cherkasyforest.org" }
      crypto_public_address { "0x1234567890abcdef1234567890abcdef12345678" }
    end
  end
end
