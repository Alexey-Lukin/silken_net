# frozen_string_literal: true

FactoryBot.define do
  factory :tiny_ml_model do
    sequence(:version) { |n| "v#{n}.0.0" }
    binary_weights_payload { "x" * 1024 }
    is_active  { false }
    tree_family { nil }

    trait :active do
      is_active { true }
    end

    trait :for_family do
      tree_family
    end
  end
end
