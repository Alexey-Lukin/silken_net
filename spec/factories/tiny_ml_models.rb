# frozen_string_literal: true

FactoryBot.define do
  factory :tiny_ml_model do
    sequence(:version) { |n| "v#{n}.0.0" }
    binary_weights_payload { "x" * 1024 }
    is_active  { false }
    tree_family { nil }
    model_format { nil }
    min_firmware_version { nil }
    rollout_percentage { 0 }

    trait :active do
      is_active { true }
    end

    trait :for_family do
      tree_family
    end

    trait :tflite do
      model_format { "tflite" }
    end

    trait :with_firmware_version do
      min_firmware_version { "v2.1.0" }
    end
  end
end
