# frozen_string_literal: true

class Tree < ApplicationRecord
  # --- ЗВ'ЯЗКИ (The Fabric of the Forest) ---
  belongs_to :cluster, optional: true
  belongs_to :tiny_ml_model, optional: true
  belongs_to :tree_family, counter_cache: true

  has_one :wallet, dependent: :destroy

  # Zero-Trust: DID дерева є ключем до його апаратного шифру
  has_one :hardware_key, foreign_key: :device_uid, primary_key: :did, dependent: :destroy

  has_one :device_calibration, dependent: :destroy

  # [ВИПРАВЛЕНО: Чорна Діра Пам'яті]: Використовуємо delete_all для швидкодії без OOM
  has_many :telemetry_logs, dependent: :delete_all

  has_many :ews_alerts, dependent: :destroy
  has_many :maintenance_records, as: :maintainable, dependent: :destroy
  has_many :ai_insights, as: :analyzable, dependent: :destroy

  # --- ДЕЛЕГУВАННЯ ---
  delegate :name, :attractor_thresholds, to: :tree_family, prefix: true

  # --- СТАН (The Lifecycle) ---
  enum :status, { active: 0, dormant: 1, removed: 2, deceased: 3 }, default: :active

  # --- СТАН ПРОШИВКИ (OTA Status Tracking) ---
  # Відстежуємо процес OTA-оновлення, щоб уникнути «чорної діри» прошивки.
  enum :firmware_update_status, {
    fw_idle: 0,        # Немає активного оновлення
    fw_pending: 1,     # Оновлення заплановано
    fw_downloading: 2, # Завантаження чанків
    fw_verifying: 3,   # Верифікація SHA-256
    fw_flashing: 4,    # Запис у Flash
    fw_failed: 5,      # Оновлення провалене
    fw_completed: 6    # Успішно оновлено
  }, prefix: :firmware, default: :fw_idle

  # --- КОНСТАНТИ (Іоністор суперконденсатор 5.5В 0.47Ф) ---
  VCAP_MIN_MV = 2800   # Мінімальна робоча напруга (нижче — STM32 втрачає mesh-relay)
  VCAP_MAX_MV = 5500   # Максимальна напруга повністю зарядженого іоністора
  LOW_POWER_MV = 3300  # Поріг критичного рівня енергії

  # Zero-Trust: Формат DID відповідає апаратній специфікації STM32 (uint32_t → 8 hex digits)
  DID_FORMAT = /\ASNET-[0-9A-F]{8}\z/

  # --- ВАЛІДАЦІЇ ---
  before_validation :normalize_did
  validates :did, presence: true, uniqueness: true,
            format: { with: DID_FORMAT, message: "має відповідати апаратному формату (SNET-XXXXXXXX)" }
  validates :latitude, numericality: { in: -90..90 }, allow_nil: true
  validates :longitude, numericality: { in: -180..180 }, allow_nil: true

  # --- КОЛБЕКИ ---
  after_create :build_default_wallet
  after_create :ensure_calibration

  # [Counter Cache]: Підтримка денормалізованого лічильника active_trees_count у Cluster.
  # Використовуємо after_commit для гарантії видимості змін іншими транзакціями.
  after_create_commit :increment_cluster_active_trees_count, if: -> { active? && cluster_id.present? }
  after_destroy_commit :decrement_cluster_active_trees_count, if: -> { active? && cluster_id.present? }
  after_update_commit :update_cluster_active_trees_count, if: -> { saved_change_to_status? || saved_change_to_cluster_id? }

  # ⚡ [ТРИГЕР СМЕРТІ]: Якщо дерево гине або зникає — ініціюємо фінансову відплату (Slashing)
  after_update_commit :trigger_slashing_protocol, if: -> { saved_change_to_status? && (removed? || deceased?) }

  # ⚡ [ГЕОПРОСТОРОВА МАТРИЦЯ]: Миттєво оновлюємо вузол на мапі при будь-якій зміні (включаючи touch)
  after_update_commit :broadcast_map_update

  # --- СКОУПИ (The Watchers) ---
  scope :active, -> { where(status: :active) }
  scope :geolocated, -> { where.not(latitude: nil, longitude: nil) }

  # [ОПТИМІЗАЦІЯ]: Використовуємо окрему колонку для швидкодії
  scope :silent, -> { where("last_seen_at < ?", 24.hours.ago) }
  # [UTC Anchor]: Використовуємо фіксований UTC для скоупу без контексту кластера.
  scope :critical_stress, -> {
    joins(:ai_insights)
      .where(ai_insights: { insight_type: :daily_health_summary, target_date: Time.current.utc.to_date - 1 })
      .where("ai_insights.stress_index > 0.8")
  }

  # --- МЕТОДИ (Intelligence) ---

  # [ВИПРАВЛЕНО: Фантомна Луна + Race Condition]:
  # GREATEST гарантує детермінованість при одночасних пакетах від різних наземних станцій Starlink
  def mark_seen!(voltage_mv = nil)
    now = Time.current

    sql = if voltage_mv
      [ "last_seen_at = GREATEST(COALESCE(last_seen_at, ?), ?), latest_voltage_mv = ?", now, now, voltage_mv ]
    else
      [ "last_seen_at = GREATEST(COALESCE(last_seen_at, ?), ?)", now, now ]
    end

    self.class.where(id: id).update_all(sql)

    # Синхронізуємо in-memory стан без reload (як update_columns) для швидкодії на hot path
    self.last_seen_at = now
    self.latest_voltage_mv = voltage_mv if voltage_mv
    broadcast_map_update
  end

  # Останній вердикт Оракула
  # [Cluster TZ]: Використовуємо часовий пояс кластера для правильної дати.
  def current_stress
    target = cluster&.local_yesterday || (Time.current.utc.to_date - 1)
    ai_insights.daily_health_summary.for_date(target).first&.stress_index || 0.0
  end

  def under_threat?
    ews_alerts.unresolved.exists?
  end

  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # IONIC INTELLIGENCE (Streaming Potential Management)
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

  # [ОПТИМІЗАЦІЯ: N+1 Загроза]: Тепер беремо значення прямо з таблиці trees
  def ionic_voltage
    latest_voltage_mv || 0
  end

  # Розрахунок заряду у % (Іоністор: лінійна крива розряду)
  def charge_percentage
    return 0 if ionic_voltage.zero?

    ((ionic_voltage - VCAP_MIN_MV).to_f / (VCAP_MAX_MV - VCAP_MIN_MV) * 100).clamp(0, 100).to_i
  end

  # Перевірка критичного рівня енергії для виживання вузла
  def low_power?
    ionic_voltage > 0 && ionic_voltage < LOW_POWER_MV
  end

  # Помічник для глибокого аудиту (використовувати тільки в show)
  def latest_telemetry
    @latest_telemetry ||= telemetry_logs.order(created_at: :desc).first
  end

  # ⚡ [ГЕОПРОСТОРОВА МАТРИЦЯ]: Трансляція вузла в Stimulus контролер
  def broadcast_map_update
    return unless latitude.present? && longitude.present?

    Turbo::StreamsChannel.broadcast_replace_to(
      "geospatial_matrix",
      target: "map_node_#{id}",
      html: Dashboard::MapNode.new(tree: self).call
    )
  end

  private

  def build_default_wallet
    create_wallet!(balance: 0, organization: cluster&.organization)
  end

  def ensure_calibration
    create_device_calibration! unless device_calibration
  end

  def normalize_did
    self.did = did.to_s.strip.upcase if did.present?
  end

  def trigger_slashing_protocol
    return unless cluster&.organization

    org_id = cluster.organization_id
    contract_ids = cluster.naas_contracts.active.pluck(:id)
    return if contract_ids.empty?

    # Bulk Slashing: один виклик Redis замість N окремих perform_async
    BurnCarbonTokensWorker.perform_bulk(
      contract_ids.map { |contract_id| [ org_id, contract_id, id ] }
    )

    Rails.logger.warn "🚨 [Ecosystem Breach] Дерево #{did} зафіксовано як #{status}. Сигнал на вилучення токенів відправлено."
  end

  # =========================================================================
  # COUNTER CACHE: active_trees_count на Cluster
  # =========================================================================

  def increment_cluster_active_trees_count
    Cluster.where(id: cluster_id).update_all("active_trees_count = active_trees_count + 1")
  end

  def decrement_cluster_active_trees_count
    Cluster.where(id: cluster_id).where("active_trees_count > 0").update_all("active_trees_count = active_trees_count - 1")
  end

  def update_cluster_active_trees_count
    old_status, new_status = saved_change_to_status || [ status_before_type_cast, status_before_type_cast ]
    old_cluster_id, new_cluster_id = saved_change_to_cluster_id || [ cluster_id, cluster_id ]

    was_active = old_status == "active" || old_status == 0
    is_active = active?

    # Декремент зі старого кластера, якщо дерево було активним
    if was_active && old_cluster_id.present?
      Cluster.where(id: old_cluster_id).where("active_trees_count > 0").update_all("active_trees_count = active_trees_count - 1")
    end

    # Інкремент у новому кластері, якщо дерево стало/залишається активним
    if is_active && new_cluster_id.present?
      Cluster.where(id: new_cluster_id).update_all("active_trees_count = active_trees_count + 1")
    end
  end
end
