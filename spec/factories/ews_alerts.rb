# frozen_string_literal: true

FactoryBot.define do
  factory :ews_alert do
    cluster
    tree
    severity { :medium }
    alert_type { :severe_drought }
    status { :active }
    message { "Alert detected." }

    trait :drought do
      severity { :medium }
      alert_type { :severe_drought }
      message { "Severe drought detected. Z-value exceeded critical bounds." }
    end

    trait :fire do
      severity { :critical }
      alert_type { :fire_detected }
      message { "Fire detected. Temperature spike above 60C threshold." }
    end
  end
end
