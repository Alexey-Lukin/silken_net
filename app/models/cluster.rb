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

  # --- ВАЛІДАЦІЇ ТА НОРМАЛІЗАЦІЯ ---
  validates :name, presence: true, uniqueness: true
  validates :region, presence: true

  # Гарантуємо, що GeoJSON не містить сміття
  normalizes :geojson_polygon, with: ->(json) { json.is_a?(Hash) ? json.deep_stringify_keys : json }

  # --- СКОУПИ ---
  scope :alphabetical, -> { order(name: :asc) }
  scope :under_threat, -> { joins(:ews_alerts).where(ews_alerts: { status: :active, severity: :critical }).distinct }

  # --- МЕТОДИ (Sector Intelligence) ---

  def total_active_trees
    trees.active.count
  end

  def mapped?
    geojson_polygon.present? && geojson_polygon["coordinates"].present?
  end

  # Агрегований індекс життєздатності (Vitality Score)
  # $$V = 1.0 - S$$ де $S$ - stress_index з добового звіту ШІ
  def health_index
    @health_index ||= begin
      insight = ai_insights.daily_health_summary.for_date(Date.yesterday).first
      insight ? (1.0 - insight.stress_index.to_f).round(2) : 1.0
    end
  end

  # Чи є критичні загрози в секторі?
  def active_threats?
    ews_alerts.unresolved.critical.exists?
  end

  # Розрахунок центроїда для фокусування карти
  def geo_center
    return nil unless mapped?

    # Витягуємо всі пари [long, lat] з полігону
    coords = geojson_polygon["coordinates"].flatten(1)
    return nil if coords.empty?

    avg_lat = coords.map(&:last).sum / coords.size
    avg_lng = coords.map(&:first).sum / coords.size

    { lat: avg_lat, lng: avg_lng }
  end

  # Повертає поточний активний NaaS-контракт
  def active_contract
    naas_contracts.active.first
  end
end
