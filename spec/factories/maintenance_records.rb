# frozen_string_literal: true

FactoryBot.define do
  factory :maintenance_record do
    association :user
    association :maintainable, factory: :tree
    action_type       { :inspection }
    performed_at      { 1.hour.ago }
    notes             { "Routine inspection of the node completed successfully." }
    labor_hours       { nil }
    parts_cost        { nil }
    hardware_verified { false }
    latitude          { nil }
    longitude         { nil }

    trait :with_gps do
      latitude  { 49.4285 }
      longitude { 32.0620 }
    end

    trait :with_cost do
      labor_hours { 2.5 }
      parts_cost  { 150.00 }
    end

    trait :hardware_verified do
      hardware_verified { true }
    end

    trait :repair do
      action_type { :repair }
      notes       { "Replaced the LoRa module and re-soldered anchor connectors." }
    end

    trait :installation do
      action_type { :installation }
      notes       { "Installed new titanium anchor and LoRa sensor unit on node." }
    end
  end
end
