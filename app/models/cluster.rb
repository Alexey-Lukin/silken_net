# frozen_string_literal: true

class Cluster < ApplicationRecord
  # --- ЗВ'ЯЗКИ (The Fabric of the Forest) ---
  belongs_to :organization

  has_many :trees, dependent: :nullify
  has_many :gateways, dependent: :nullify

  # [ВИПРАВЛЕНО]: Захист Фінансової Історії (Immutable Audit Trail).
  # Кластер неможливо видалити, поки в ньому є діючі NaaS-контракти чи страховки.
  # Це критично для Web3-звітності та довіри інвесторів.
  has_many :naas_contracts, dependent: :restrict_with_error
  has_many :parametric_insurances, dependent: :restrict_with_error

  # Прямий доступ до тривог усього сектора
  has_many :ews_alerts, dependent: :destroy
  # Поліморфні прогнози та підсумки (Daily Health Summary)
  has_many :ai_insights, as: :analyzable, dependent: :destroy

  # --- JSONB SETTINGS (The Biome Adaptation) ---
  store_accessor :environmental_settings,
                 :custom_fire_threshold,
                 :seismic_sensitivity_threshold,
                 :timezone

  # --- ВАЛІДАЦІЇ ТА НОРМАЛІЗАЦІЯ ---
  validates :name, presence: true, uniqueness: true
  validates :region, presence: true

  validates :custom_fire_threshold, :seismic_sensitivity_threshold,
            numericality: { greater_than: 0 }, allow_nil: true

  normalizes :geojson_polygon, with: ->(json) { json.is_a?(Hash) ? json.deep_stringify_keys : json }

  # --- СКОУПИ ---
  scope :alphabetical, -> { order(name: :asc) }

  # [СИНХРОНІЗОВАНО]: Використовуємо статус :active, що відповідає скоупу unresolved в EwsAlert.
  scope :under_threat, -> {
    joins(:ews_alerts).where(ews_alerts: { status: :active, severity: :critical }).distinct
  }

  # --- МЕТОДИ (Sector Intelligence) ---

  def total_active_trees
    trees.active.count
  end

  def mapped?
    geojson_polygon.present? && geojson_polygon["coordinates"].present?
  end

  # Агрегований індекс життєздатності (Vitality Score)
  # Використовуємо кешоване значення з БД, яке оновлюється ClusterHealthCheckWorker.
  # Якщо кешованого значення немає, повертаємо 1.0 (ідеальне здоров'я за замовчуванням).
  def health_index
    read_attribute(:health_index) || 1.0
  end

  # [UTC/Cluster TZ Anchor]: Вчорашня дата в часовому поясі кластера.
  # Якщо timezone не задано — використовуємо UTC для детермінованості арбітражу.
  # Гарантує, що «вчора» у Черкасах та «вчора» у джунглях Амазонки — це правильна дата.
  def local_yesterday
    Time.use_zone(timezone.presence || "UTC") { Date.yesterday }
  end

  # Перерахунок health_index на основі даних ШІ (використовується у ClusterHealthCheckWorker)
  # $$V = 1.0 - S$$ де $S$ - stress_index з добового звіту ШІ
  def recalculate_health_index!(target_date = local_yesterday)
    insight = ai_insights.daily_health_summary.for_date(target_date).first
    new_value = insight ? (1.0 - insight.stress_index.to_f).round(2) : 1.0
    update_column(:health_index, new_value)
    new_value
  end

  # Чи є критичні загрози в секторі?
  def active_threats?
    # [СИНХРОНІЗОВАНО]: Тепер назва скоупу збігається з логікою EwsAlert
    ews_alerts.unresolved.critical.exists?
  end

  # [ВИПРАВЛЕНО]: Глибина GeoJSON (Resilient Centroid).
  # Тепер метод збирає всі пари координат незалежно від того, чи це Polygon, чи MultiPolygon.
  def geo_center
    return nil unless mapped?

    # Повністю розгортаємо масив і групуємо по два значення (lng, lat)
    # Це імунітет до MultiPolygon, де вкладеність масивів глибша.
    all_points = geojson_polygon["coordinates"].flatten.each_slice(2).to_a
    return nil if all_points.empty?

    avg_lat = all_points.map(&:last).sum / all_points.size
    avg_lng = all_points.map(&:first).sum / all_points.size

    { lat: avg_lat, lng: avg_lng }
  end

  # [СИНХРОНІЗОВАНО]: Повертає поточний активний NaaS-контракт.
  # Використовує уніфікований скоуп .active замість .active_contracts
  def active_contract
    naas_contracts.active.first
  end
end
