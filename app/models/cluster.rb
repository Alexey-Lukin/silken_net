# frozen_string_literal: true

class Cluster < ApplicationRecord
  # --- ЗВ'ЯЗКИ (The Fabric of the Forest) ---
  belongs_to :organization
  
  has_many :trees, dependent: :nullify
  has_many :gateways, dependent: :nullify
  has_many :naas_contracts, dependent: :destroy
  
  # Прямий доступ до тривог усього сектора
  has_many :ews_alerts, dependent: :destroy
  # Страхові поліси, прив'язані до конкретної локації
  has_many :parametric_insurances, dependent: :destroy
  # Поліморфні прогнози та підсумки (Daily Health Summary)
  has_many :ai_insights, as: :analyzable, dependent: :destroy

  # --- ВАЛІДАЦІЇ ---
  validates :name, presence: true, uniqueness: true
  validates :region, presence: true

  # --- МЕТОДИ (Sector Intelligence) ---

  def total_active_trees
    trees.active.count
  end

  def mapped?
    geojson_polygon.present?
  end

  # [ВИПРАВЛЕНО]: Агрегований індекс стресу (Health Index)
  # Беремо останній добовий інсайт, згенерований InsightGeneratorService
  def health_index
    insight = ai_insights.daily_health_summary
                         .where(target_date: Date.yesterday)
                         .first
    
    # Повертаємо інвертований індекс (1.0 - стрес = здоров'я)
    insight ? (1.0 - insight.stress_index).round(2) : 1.0
  end

  # [ВИПРАВЛЕНО]: Чи є критичні загрози?
  # Припускаємо, що unresolved - це алерти без зафіксованого часу вирішення
  def active_threats?
    ews_alerts.where(resolved_at: nil).critical.exists?
  end

  # Допоміжний метод для карти: центр кластера
  # (Корисно для фокусування камери в мобільному додатку)
  def geo_center
    return nil unless mapped?
    # Логіка парсингу geojson_polygon для знаходження центроїда
    # Наразі повертаємо першу точку для прикладу
    geojson_polygon["coordinates"]&.first&.first
  end
end
