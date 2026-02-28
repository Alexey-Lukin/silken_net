# frozen_string_literal: true

class AiInsight < ApplicationRecord
  # --- ЗВ'ЯЗКИ ---
  # Прогноз/Звіт може стосуватися цілого лісу (Cluster) або конкретного Дерева (Tree)
  belongs_to :analyzable, polymorphic: true

  # --- ТИПИ ІНСАЙТІВ (Ретроспектива та Прогноз) ---
  enum :insight_type, {
    daily_health_summary: 0,  # [РЕАЛЬНІСТЬ]: Вчорашній звіт (для Страховки та D-MRV)
    drought_probability: 1,   # [ПРОГНОЗ]: Ймовірність посухи в наступні 30 днів
    carbon_yield_forecast: 2, # [ПРОГНОЗ]: Генерація токенів на наступний квартал
    biodiversity_trend: 3     # [ПРОГНОЗ]: Тренд стабільності Атрактора Лоренца
  }, prefix: true

  # --- ВАЛІДАЦІЇ ---
  validates :insight_type, :target_date, presence: true
  
  # Для прогнозів: відсоток впевненості ШІ (0.0 - 100.0)
  validates :probability_score, numericality: { in: 0.0..100.0 }, allow_nil: true
  
  # Для ретроспективи: індекс стресу (0.0 - 1.0, де 1.0 - це смерть/критика)
  validates :stress_index, numericality: { in: 0.0..1.0 }, allow_nil: true

  # reasoning / recommendation: JSONB або Text для текстового/структурованого висновку

  # --- СКОУПИ ---
  scope :highly_probable, -> { where("probability_score > ?", 80.0) }
  scope :upcoming, -> { where("target_date >= ?", Date.current) }
  scope :critical_stress, -> { insight_type_daily_health_summary.where("stress_index >= ?", 0.8) }

  # --- МЕТОДИ ---
  # Візуалізація впевненості (для UI)
  def confidence_level
    return :n_a unless probability_score

    case probability_score
    when 0.0...40.0 then :low
    when 40.0...75.0 then :medium
    else :high
    end
  end
  
  # Зручний предикат для перевірки, чи є цей запис фактом, чи лише передбаченням
  def forecast?
    !insight_type_daily_health_summary?
  end
end
