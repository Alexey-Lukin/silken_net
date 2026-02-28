# frozen_string_literal: true

class AiInsight < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  # Прогноз/Звіт може стосуватися Cluster (Кластер), Tree (Дерево) або Organization
  belongs_to :analyzable, polymorphic: true

  # --- ТИПИ ІНСАЙТІВ (Ретроспектива та Прогноз) ---
  enum :insight_type, {
    daily_health_summary: 0,  # [РЕАЛЬНІСТЬ]: Вчорашній звіт (база для D-MRV)
    drought_probability: 1,   # [ПРОГНОЗ]: Ймовірність посухи
    carbon_yield_forecast: 2, # [ПРОГНОЗ]: Емісія токенів
    biodiversity_trend: 3    # [ПРОГНОЗ]: Стабільність Атрактора Лоренца
  }, prefix: true

  # --- СТРУКТУРОВАНІ ДАНІ (The Reasoning Engine) ---
  # Використовуємо JSONB для гнучкого пояснення логіки ШІ
  store_accessor :reasoning, :avg_z, :max_temp, :anomaly_vector
  store_accessor :recommendation, :action_required, :priority

  # --- ВАЛІДАЦІЇ ---
  validates :insight_type, :target_date, presence: true

  # Унікальність: Один звіт про здоров'я на об'єкт на день
  validates :target_date, uniqueness: {
    scope: [ :analyzable_id, :analyzable_type, :insight_type ],
    message: "вже зафіксовано для цього об'єкта"
  }, if: :daily_health_summary?

  validates :probability_score, numericality: { in: 0.0..100.0 }, allow_nil: true
  validates :stress_index, numericality: { in: 0.0..1.0 }, allow_nil: true

  # --- СКОУПИ ---
  scope :highly_probable, -> { where("probability_score > ?", 80.0) }
  scope :upcoming, -> { where("target_date >= ?", Date.current) }
  scope :critical_stress, -> { daily_health_summary.where("stress_index >= ?", 0.8) }
  scope :for_date, ->(date) { where(target_date: date) }

  # --- МЕТОДИ (The Lens of Truth) ---

  # Чи вважається цей стан порушенням умов контракту?
  # Використовується в Slashing Protocol
  def contract_breach?
    daily_health_summary? && stress_index.to_f >= 0.8
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

  # Швидка перевірка стану
  def status_label
    return "Forecast" if forecast?
    stress_index.to_f < 0.3 ? "Stable" : "Stressed"
  end
end
