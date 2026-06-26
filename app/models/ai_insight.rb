# frozen_string_literal: true

class AiInsight < ApplicationRecord
  # [ARCH.46] Поріг stress_index, за якого дерево рахується критично стресованим на SLASH-шляху —
  # спільний для ТРИГЕРА (ContractHealthCheckService: >20% дерев ≥ цього) і РОЗМІРУ
  # (BlockchainBurningService#calculate_damage_ratio: damage = частка дерев ≥ цього). Одна
  # константа, щоб тригер і damage не розходились (був баг: тригер 0.83 vs damage 1.0 → 100% over-burn).
  # Канон-дім порога — 05_06 STRESS_THRESHOLD + 05_05 §3/§7. ⚠️ НЕ плутати з `critical_stress`-scope /
  # `contract_breach?` (0.8 — ширший insurance/UI-концепт, свідомо окремий від slash-порога).
  SLASH_STRESS_THRESHOLD = 0.83

  # --- ЗВ'ЯЗКИ ---
  # Прогноз/Звіт може стосуватися Cluster (Кластер), Tree (Дерево) або Organization
  belongs_to :analyzable, polymorphic: true

  # --- ТИПИ ІНСАЙТІВ (Ретроспектива та Прогноз) ---
  enum :insight_type, {
    daily_health_summary: 0,  # [РЕАЛЬНІСТЬ]: Вчорашній звіт (база для D-MRV)
    drought_probability: 1,   # [ПРОГНОЗ]: Ймовірність посухи
    carbon_yield_forecast: 2, # [ПРОГНОЗ]: Емісія токенів
    biodiversity_trend: 3     # [ПРОГНОЗ]: Стабільність Атрактора Лоренца
  }

  # --- СТРУКТУРОВАНІ ДАНІ (The Reasoning Engine) ---
  # Використовуємо JSONB для гнучкого пояснення логіки ШІ
  # fraud_detected винесено в окрему boolean колонку для коректної типізації та швидкого пошуку
  store_accessor :reasoning, :avg_z, :max_temp, :anomaly_vector, :avg_vcap, :deviation_from_baseline
  store_accessor :recommendation, :action_required, :priority

  # --- ВАЛІДАЦІЇ ---
  validates :insight_type, :target_date, presence: true

  # Унікальність: Один звіт про здоров'я на об'єкт на день на джерело (Oracle Consensus)
  validates :target_date, uniqueness: {
    scope: [ :analyzable_id, :analyzable_type, :insight_type, :model_source ],
    message: "вже зафіксовано для цього об'єкта"
  }, if: :daily_health_summary?

  validates :probability_score, numericality: { in: 0.0..100.0 }, allow_nil: true
  validates :stress_index, numericality: { in: 0.0..1.0 }, allow_nil: true

  # --- СКОУПИ ---
  scope :highly_probable, -> { where("probability_score > ?", 80.0) }
  scope :upcoming, -> { where("target_date >= ?", Time.current.utc.to_date) }
  scope :critical_stress, -> { daily_health_summary.where("stress_index >= ?", 0.8) }
  scope :for_date, ->(date) { where(target_date: date) }
  scope :fraudulent, -> { where(fraud_detected: true) }

  # Evidence Persistence: знайти інсайти, що посилаються на конкретний telemetry log
  scope :referencing_log, ->(log_id) { where("source_log_ids @> ARRAY[?]::bigint[]", log_id.to_i) }

  # Full-text search in reasoning JSONB (uses tsvector GIN index).
  # The idx_ai_insights_reasoning_gin (plain JSONB GIN) only supports @> containment.
  # This scope uses the dedicated tsvector GIN index idx_ai_insights_reasoning_fts
  # for actual word-level text search on reasoning->>'description'.
  scope :search_reasoning, ->(query) {
    where(
      "to_tsvector('simple', COALESCE(reasoning->>'description', '')) @@ plainto_tsquery('simple', ?)",
      query.to_s
    )
  }

  # --- МЕТОДИ (The Lens of Truth) ---

  # Чи вважається цей стан порушенням умов контракту?
  # Використовується в Slashing Protocol
  # Порівнюємо decimal напряму — без .to_f, щоб уникнути похибки плаваючої коми
  def contract_breach?
    daily_health_summary? && stress_index.present? && stress_index >= BigDecimal("0.8")
  end

  # Візуалізація впевненості для Патрульного
  def confidence_level
    return :n_a unless probability_score

    case probability_score
    when 0.0...40.0 then :low
    when 40.0...75.0 then :medium
    else :high
    end
  end

  def forecast?
    !daily_health_summary?
  end

  # Evidence Persistence: telemetry logs, що стали підставою для цього інсайту
  # source_log_ids зберігає integer ID (перший елемент composite key партиціонованої таблиці)
  def source_logs
    return TelemetryLog.none if source_log_ids.blank?

    TelemetryLog.where(id: source_log_ids)
  end

  # Прив'язати telemetry logs як докази для інсайту
  def attach_evidence!(log_ids)
    update!(source_log_ids: (source_log_ids + Array(log_ids)).uniq)
  end

  # Швидка перевірка стану
  def status_label
    return "Forecast" if forecast?
    return "Fraud Detected" if fraud_detected?
    stress_index.present? && stress_index >= BigDecimal("0.3") ? "Stressed" : "Stable"
  end
end
