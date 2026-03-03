# frozen_string_literal: true

FactoryBot.define do
  factory :tree_family do
    sequence(:name) { |n| "Tree Family #{n}" }
    baseline_impedance { 1200 }
    critical_z_min { 5.0 }
    critical_z_max { 45.0 }

    trait :scots_pine do
      name { "Scots Pine" }
      baseline_impedance { 1200 }
      critical_z_min { 5.0 }
      critical_z_max { 45.0 }
    end

    trait :common_oak do
      name { "Common Oak" }
      baseline_impedance { 1800 }
      critical_z_min { 8.0 }
      critical_z_max { 40.0 }
    end
  end
end
