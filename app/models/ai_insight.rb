# frozen_string_literal: true

class AiInsight < ApplicationRecord
  # Прогноз може стосуватися цілого лісу (Кластера) або конкретного Дерева
  belongs_to :analyzable, polymorphic: true

  # Типи прогнозів
  enum :insight_type, {
    drought_probability: 0, # Ймовірність посухи в наступні 30 днів
    carbon_yield_forecast: 1, # Прогноз генерації токенів на наступний квартал
    biodiversity_trend: 2   # Тренд стабільності Атрактора Лоренца
  }, prefix: true

  # probability_score: відсоток впевненості ШІ (0.0 - 100.0)
  # target_date: дата, на яку робиться прогноз
  # reasoning: JSON або текст (чому ШІ зробив такий висновок, важливо для аудиту)

  validates :insight_type, :probability_score, :target_date, presence: true
  validates :probability_score, inclusion: { in: 0.0..100.0 }

  scope :highly_probable, -> { where("probability_score > ?", 80.0) }
end
