# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

FactoryBot.define do
  factory :tree_family do
    # [TEST.11] `tree_families.name` — unique-індекс; суфікс розводить процеси.
    # `scientific_name` (теж unique) фабрика лишає nil, а NULL-и індекс не
    # конфліктує — рандомізувати нічого.
    sequence(:name) { |n| "Tree Family #{n}-#{SecureRandom.hex(3)}" }
    critical_z_min { 5.0 }
    critical_z_max { 45.0 }
    carbon_sequestration_coefficient { 1.0 }

    trait :scots_pine do
      name { "Scots Pine" }
      scientific_name { "Pinus sylvestris" }
      critical_z_min { 5.0 }
      critical_z_max { 45.0 }
      carbon_sequestration_coefficient { 0.8 }
    end

    trait :common_oak do
      name { "Common Oak" }
      scientific_name { "Quercus robur" }
      critical_z_min { 8.0 }
      critical_z_max { 40.0 }
      carbon_sequestration_coefficient { 1.5 }
    end
  end
end
