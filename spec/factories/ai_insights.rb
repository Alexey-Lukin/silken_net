# frozen_string_literal: true

FactoryBot.define do
  factory :ai_insight do
    analyzable { association(:tree) }
    insight_type { :daily_health_summary }
    target_date { Time.current.utc.to_date - 1 }
    stress_index { 0.1 }
    summary { "ГОМЕОСТАЗ: Стан дерева ідеальний." }
  end
end
