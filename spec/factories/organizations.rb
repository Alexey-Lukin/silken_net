# frozen_string_literal: true

FactoryBot.define do
  factory :organization do
    sequence(:name) { |n| "Organization #{n}" }
    sequence(:billing_email) { |n| "billing#{n}@example.org" }
    sequence(:crypto_public_address) { |n| "0x#{'%040x' % n}" }

    trait :forest_fund do
      name { "Cherkasy Forest Fund" }
      billing_email { "billing@cherkasyforest.org" }
      crypto_public_address { "0x1234567890abcdef1234567890abcdef12345678" }
    end
  end
end
