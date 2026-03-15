# frozen_string_literal: true

require "rumale/ensemble/random_forest_classifier"
require "numo/narray"

namespace :ai do
  desc "Train Random Forest model for stress_index prediction using historical AiInsight + TelemetryLog data"
  task train: :environment do
    MODEL_PATH = Rails.root.join("lib/assets/silken_forest.marshal").freeze

    Rails.logger.info "🧠 [AI Train] Збір навчальних даних з AiInsight + TelemetryLog..."

    # ⚡ [ANTI-N+1]: Завантажуємо всі daily_health_summary інсайти з JSONB reasoning одним запитом.
    insights = AiInsight.daily_health_summary.where.not(stress_index: nil)

    if insights.count < 50
      Rails.logger.warn "⚠️ [AI Train] Недостатньо даних для тренування (#{insights.count} < 50). Скасовано."
      next
    end

    features = []
    labels = []

    insights.find_each do |insight|
      reasoning = insight.reasoning || {}

      avg_temp = insight.average_temperature.to_f
      avg_vcap = reasoning["avg_vcap"].to_f
      avg_z = reasoning["avg_z"].to_f
      sap_deviation = reasoning["deviation_from_baseline"].to_f
      max_acoustic = reasoning["max_acoustic"].to_f

      features << [ avg_temp, avg_vcap, avg_z, sap_deviation, max_acoustic ]

      # Бінарна мітка: 1 (стрес/аномалія) або 0 (гомеостаз)
      labels << (insight.stress_index >= 0.5 ? 1 : 0)
    end

    x = Numo::DFloat.cast(features)
    y = Numo::Int32.cast(labels)

    positive_count = labels.count(1)
    negative_count = labels.count(0)
    Rails.logger.info "📊 [AI Train] Датасет: #{labels.size} зразків (stress=#{positive_count}, healthy=#{negative_count})"

    # RandomForestClassifier: 100 estimators, max_depth 10
    model = Rumale::Ensemble::RandomForestClassifier.new(
      n_estimators: 100,
      max_depth: 10,
      random_seed: 42
    )

    Rails.logger.info "🏋️ [AI Train] Тренування Random Forest (100 estimators, max_depth=10)..."
    model.fit(x, y)

    # Серіалізація моделі
    File.binwrite(MODEL_PATH, Marshal.dump(model))
    Rails.logger.info "✅ [AI Train] Модель збережено: #{MODEL_PATH} (#{File.size(MODEL_PATH)} bytes)"
  end
end
