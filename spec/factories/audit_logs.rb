# frozen_string_literal: true

FactoryBot.define do
  factory :audit_log do
    user
    organization { user.organization }
    action { "update_settings" }
    metadata { { field: "critical_z", old_value: 100, new_value: 200 } }

    trait :with_auditable do
      association :auditable, factory: :cluster
    end
  end
end
