# frozen_string_literal: true

FactoryBot.define do
  factory :bio_contract_firmware do
    sequence(:version) { |n| "#{n}.0.0" }
    bytecode_payload { "AABBCCDD" }
    is_active { false }
    target_hardware_type { nil }
    tree_family { nil }
    compatible_hardware_versions { [] }

    trait :active do
      is_active { true }
    end

    trait :for_tree do
      target_hardware_type { "Tree" }
    end

    trait :for_gateway do
      target_hardware_type { "Gateway" }
    end

    trait :for_family do
      tree_family
    end

    trait :with_hardware_versions do
      compatible_hardware_versions { %w[v1.0 v1.1 v2.0] }
    end
  end
end
