# frozen_string_literal: true

class QuantumStressAnalyzerWorker
  include Sidekiq::Job

  # Черга `alerts` (пріоритет 2) — це частина Early Warning System.
  # Аналіз ентропії є передстресовим детектором: виявляє деградацію
  # ДО появи фізичних симптомів (bio_status: stress/anomaly).
  sidekiq_options queue: "alerts", retry: 3

  # Поріг критичної ентропії: нижче цього значення ентропія вказує
  # на аномальну гомогенізацію Z-значень у кластері.
  # 0.65 обрано як баланс між чутливістю та false-positive:
  # - Здоровий ліс: entropy ≈ 0.75-0.95 (різноманітні Z-значення)
  # - Помірний стрес: entropy ≈ 0.50-0.75 (починається кореляція)
  # - Критичний стрес: entropy < 0.50 (масова гомогенізація)
  # Поріг 0.65 дає ~15-хвилинне попередження перед каскадом stress alerts.
  CRITICAL_ENTROPY_THRESHOLD = 0.65

  # Часове вікно для збору Z-значень (partition-aware).
  # 24 години забезпечує достатню статистичну вибірку для Shannon entropy.
  ANALYSIS_WINDOW = 24.hours

  # Redis silence filter: не більше 1 тривоги на кластер за 1 годину.
  # Це узгоджено з InsightGeneratorService (щоденний) та AlertDispatchService (5 хв per tree).
  SILENCE_PERIOD = 1.hour

  def perform(cluster_id)
    cluster = Cluster.find_by(id: cluster_id)
    return unless cluster

    # 1. ЗБІР Z-ЗНАЧЕНЬ (Partition-Aware Query)
    # Запит включає created_at для partition pruning на RANGE-партиціонованій таблиці.
    cutoff = ANALYSIS_WINDOW.ago
    z_values = TelemetryLog
      .joins(:tree)
      .where(trees: { cluster_id: cluster_id })
      .where(created_at: cutoff..)
      .where.not(z_value: nil)
      .pluck(:z_value)
      .map(&:to_f)

    # 2. ОБЧИСЛЕННЯ ЕНТРОПІЇ
    entropy_score = Analytics::EntropyCalculatorService.call(z_values)

    # Недостатньо даних для аналізу — пропускаємо без помилки
    return if entropy_score.nil?

    # 3. ДЕНОРМАЛІЗАЦІЯ (аналогічно health_index)
    cluster.update_column(:entropy_score, entropy_score)

    # 4. PROMETHEUS METRIC
    SilkenNet::Metrics::CLUSTER_ENTROPY_SCORE.set(
      entropy_score,
      labels: { cluster_id: cluster_id.to_s }
    )

    # 5. EWS ALERTING (якщо поріг перетнуто)
    if entropy_score < CRITICAL_ENTROPY_THRESHOLD
      create_pre_stress_alert!(cluster, entropy_score, z_values.size)
    end

    Rails.logger.info(
      "🎲 [Entropy] Кластер #{cluster.name}: entropy=#{entropy_score}, " \
      "samples=#{z_values.size}, threshold=#{CRITICAL_ENTROPY_THRESHOLD}"
    )
  end

  private

  def create_pre_stress_alert!(cluster, entropy_score, sample_count)
    # Redis Silence Filter — узгоджено з AlertDispatchService
    silence_key = "ews_silence:cluster:#{cluster.id}:quantum_pre_stress"
    return if Rails.cache.exist?(silence_key)

    EwsAlert.create!(
      cluster: cluster,
      severity: :medium,
      alert_type: :quantum_pre_stress,
      message: "🎲 ПЕРЕДСТРЕСОВИЙ СИГНАЛ: Ентропія Z-розподілу кластера #{cluster.name} " \
               "знизилась до #{entropy_score} (поріг: #{CRITICAL_ENTROPY_THRESHOLD}). " \
               "Аналіз #{sample_count} вимірювань за останні 24 години вказує на " \
               "гомогенізацію відповідей дерев — можливий початок лісового стресу."
    )

    Rails.cache.write(silence_key, true, expires_in: SILENCE_PERIOD)

    # Інвалідація кешу прогнозу Оракула (аналогічно AlertDispatchService)
    Rails.cache.delete("oracle_expected_yield_24h")

    Rails.logger.warn(
      "🚨 [EWS Entropy] quantum_pre_stress | Cluster #{cluster.name} | " \
      "entropy=#{entropy_score} < #{CRITICAL_ENTROPY_THRESHOLD}"
    )
  end
end
