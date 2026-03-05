# frozen_string_literal: true

FactoryBot.define do
  factory :parametric_insurance do
    organization
    cluster
    status        { :active }
    trigger_event { :critical_fire }
    token_type    { :carbon_coin }
    payout_amount  { 100_000 }
    threshold_value { 30 }

    trait :triggered do
      status { :triggered }
    end

    trait :expired do
      status { :expired }
    end

    trait :drought do
      trigger_event { :extreme_drought }
    end
  end
end
