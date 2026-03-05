# frozen_string_literal: true

FactoryBot.define do
  factory :tree_family do
    sequence(:name) { |n| "Tree Family #{n}" }
    baseline_impedance { 1200 }
    critical_z_min { 5.0 }
    critical_z_max { 45.0 }
    carbon_sequestration_coefficient { 1.0 }

    trait :scots_pine do
      name { "Scots Pine" }
      scientific_name { "Pinus sylvestris" }
      baseline_impedance { 1200 }
      critical_z_min { 5.0 }
      critical_z_max { 45.0 }
      carbon_sequestration_coefficient { 0.8 }
    end

    trait :common_oak do
      name { "Common Oak" }
      scientific_name { "Quercus robur" }
      baseline_impedance { 1800 }
      critical_z_min { 8.0 }
      critical_z_max { 40.0 }
      carbon_sequestration_coefficient { 1.5 }
    end
  end
end
