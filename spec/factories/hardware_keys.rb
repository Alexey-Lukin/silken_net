# frozen_string_literal: true

FactoryBot.define do
  factory :hardware_key do
    sequence(:device_uid, 900_000) { |n| "SNET-%08X" % n }
    aes_key_hex { SecureRandom.hex(32).upcase }
    previous_aes_key_hex { nil }

    trait :for_tree do
      association :tree, factory: :tree, strategy: :create
      device_uid { tree.did }
    end

    trait :for_gateway do
      association :gateway, factory: :gateway, strategy: :create
      device_uid { gateway.uid }
    end

    trait :with_grace_period do
      previous_aes_key_hex { SecureRandom.hex(32).upcase }
    end
  end
end
