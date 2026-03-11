# frozen_string_literal: true

FactoryBot.define do
  factory :wallet do
    tree
    balance { 5000.0 }
    hadron_kyc_status { "approved" }
    sequence(:crypto_public_address) { |n| "0x#{'a' * 4}#{'%036x' % n}" }
  end
end
