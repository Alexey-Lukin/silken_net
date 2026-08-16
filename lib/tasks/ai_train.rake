# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

require "rumale/ensemble/random_forest_classifier"
require "numo/narray"

namespace :ai do
  desc "Train Random Forest model for stress_index prediction using historical AiInsight + TelemetryLog data"
  task train: :environment do
    model_path = InsightGeneratorService::MODEL_PATH

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

      # Feature vector: [avg_temp, avg_vcap, avg_z, max_acoustic]
      # Must match the order in InsightGeneratorService#calculate_stress_index
      avg_temp = insight.average_temperature.to_f
      avg_vcap = reasoning["avg_vcap"].to_f
      avg_z = reasoning["avg_z"].to_f
      max_acoustic = reasoning["max_acoustic"].to_f

      features << [ avg_temp, avg_vcap, avg_z, max_acoustic ]

      # Бінарна мітка: 1 (стрес/аномалія) або 0 (гомеостаз).
      # Поріг 0.5 визначає клас для навчання; окремий поріг 0.83 використовується
      # у ContractHealthCheckService для активації Slashing Protocol.
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

    # Серіалізація моделі + SHA256 дайджест для верифікації цілісності при завантаженні
    model_data = Marshal.dump(model)
    digest = OpenSSL::Digest::SHA256.hexdigest(model_data)

    File.binwrite(model_path, model_data)
    File.write(InsightGeneratorService::MODEL_DIGEST_PATH, digest)

    Rails.logger.info "✅ [AI Train] Модель збережено: #{model_path} (#{File.size(model_path)} bytes, SHA256: #{digest})"
  end
end
