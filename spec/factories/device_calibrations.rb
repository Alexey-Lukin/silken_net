# frozen_string_literal: true

FactoryBot.define do
  factory :device_calibration do
    tree
    temperature_offset_c { 0.0 }
    impedance_offset_ohms { 0 }
    vcap_coefficient { 1.0 }

    trait :critical_drift do
      temperature_offset_c { 6.0 }
      impedance_offset_ohms { 600 }
    end
  end
end
