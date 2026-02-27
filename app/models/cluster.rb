# frozen_string_literal: true

class Cluster < ApplicationRecord
  # --- ЗВ'ЯЗКИ (The Fabric of the Forest) ---
  # Кожен лісовий кластер належить юридичній особі
  belongs_to :organization
  
  has_many :trees, dependent: :nullify
  has_many :gateways, dependent: :nullify
  has_many :naas_contracts, dependent: :destroy
  
  # [НОВЕ]: Прямий доступ до тривог усього сектора
  has_many :ews_alerts, dependent: :destroy
  # [НОВЕ]: Страхові поліси, прив'язані до конкретної локації
  has_many :parametric_insurances, dependent: :destroy
  # [НОВЕ]: Поліморфні прогнози для всього масиву
  has_many :ai_insights, as: :analyzable, dependent: :destroy

  # --- ВАЛІДАЦІЇ ---
  validates :name, presence: true, uniqueness: true
  validates :region, presence: true

  # Додаткові поля в базі:
  # - geojson_polygon: jsonb (Межі лісу для карти MapLibre/Leaflet)
  # - climate_type: string (Наприклад, "Помірний", "Тропічний")

  # --- МЕТОДИ (Sector Intelligence) ---

  def total_active_trees
    trees.active.count # Використовуємо скоуп :active з моделі Tree
  end

  # [НОВЕ]: Перевірка, чи має сектор картографічні дані
  def mapped?
    geojson_polygon.present?
  end

  # [НОВЕ]: Агрегований індекс стресу для всього кластера
  # Використовується для швидкого відображення стану лісу на глобальній карті
  def health_index
    return 0 if trees.empty?
    
    # Середнє значення індексу стресу з останніх AI інсайтів дерев
    ai_insights.drought_probability.upcoming.average(:probability_score).to_f
  end

  # [НОВЕ]: Чи є критичні загрози в цьому секторі прямо зараз?
  def active_threats?
    ews_alerts.unresolved.critical.exists?
  end
end
