# frozen_string_literal: true

FactoryBot.define do
  factory :actuator do
    sequence(:name) { |n| "Actuator #{n}" }
    sequence(:endpoint) { |n| "ep-#{n}" }
    device_type { :water_valve }
    state { :idle }
    gateway

    trait :water_valve do
      device_type { :water_valve }
    end

    trait :fire_siren do
      device_type { :fire_siren }
    end

    trait :seismic_beacon do
      device_type { :seismic_beacon }
    end
  end
end
