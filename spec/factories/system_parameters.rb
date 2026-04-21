# frozen_string_literal: true

FactoryBot.define do
  factory :system_parameter do
    sequence(:key) { |n| "param_#{n}" }
    value { "10.0" }
    value_type { "float" }
    category { "general" }
    source { "default" }
    description { "Test parameter" }

    trait :lorenz_sigma do
      key { "lorenz_sigma" }
      value { "10.0" }
      value_type { "float" }
      category { "lorenz" }
      min_value { 5.0 }
      max_value { 30.0 }
      description { "Lorenz attractor σ (sigma) parameter" }
    end

    trait :lorenz_rho do
      key { "lorenz_rho" }
      value { "28.0" }
      value_type { "float" }
      category { "lorenz" }
      min_value { 10.0 }
      max_value { 50.0 }
      description { "Lorenz attractor ρ (rho) parameter" }
    end

    trait :emission_threshold do
      key { "emission_threshold" }
      value { "10000" }
      value_type { "integer" }
      category { "tokenomics" }
      min_value { 1000 }
      max_value { 100_000 }
      description { "Growth points required to mint 1 SCC" }
    end

    trait :dynamic_tax_rate do
      key { "dynamic_tax_rate" }
      value { "0.02" }
      value_type { "decimal" }
      category { "minting" }
      min_value { 0 }
      max_value { 0.10 }
      description { "DAO Treasury dynamic tax rate (fraction)" }
    end

    trait :insurance_pool_threshold do
      key { "insurance_pool_threshold" }
      value { "100000" }
      value_type { "integer" }
      category { "insurance" }
      description { "SCC threshold below which dynamic tax is active" }
    end

    trait :boolean_param do
      key { "feature_flag" }
      value { "true" }
      value_type { "boolean" }
      category { "general" }
    end

    trait :json_param do
      key { "json_config" }
      value { '{"enabled":true,"threshold":0.5}' }
      value_type { "json" }
      category { "general" }
    end

    trait :from_governance do
      source { "governance" }
    end

    trait :from_admin do
      source { "admin" }
    end
  end
end
