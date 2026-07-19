# frozen_string_literal: true

class Tree < ApplicationRecord
  include AASM
  include Firmwareable
  include GeoLocatable
  include NormalizeIdentifier

  # Polymorphic identifier для UI/serializers (наприклад, MaintenanceRecord з
  # maintainable: Tree | Gateway). Дозволяє писати `record.maintainable.display_identifier`
  # замість `&.try(:did) || &.try(:uid)` duck-typing у 3 callsites.
  alias_attribute :display_identifier, :did

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

  # [ВИПРАВЛЕНО: Чорна Діра Пам'яті]: Використовуємо delete_all для масових таблиць,
  # щоб уникнути OOM при видаленні дерева з мільйонами записів.
  has_many :ews_alerts, dependent: :delete_all
  has_many :maintenance_records, as: :maintainable, dependent: :delete_all
  has_many :ai_insights, as: :analyzable, dependent: :delete_all

  # --- ДЕЛЕГУВАННЯ ---
  delegate :name, :attractor_thresholds, to: :tree_family, prefix: true

  # [FW.8] Global Lorenz defaults — match firmware/bio_contracts/bio_contract.rb
  # BioContract::CRITICAL_Z_MIN/MAX/OPTIMAL_Z_TARGET. Used as final fallback when
  # neither cluster override nor tree_family per-species value is set.
  GLOBAL_LORENZ_Z_MIN     = 2.0
  GLOBAL_LORENZ_Z_MAX     = 45.0
  GLOBAL_LORENZ_Z_OPTIMAL = 29.0

  # --- СТАН (The Lifecycle) ---
  enum :status, { active: 0, dormant: 1, removed: 2, deceased: 3 }, default: :active

  # =========================================================================
  # ЖИТТЄВИЙ ЦИКЛ ДЕРЕВА (AASM State Machine)
  # =========================================================================
  aasm column: :status, enum: true, whiny_persistence: true do
    state :active, initial: true
    state :dormant
    state :removed
    state :deceased

    # Дерево входить у зимовий сон / суху фазу
    event :suspend do
      transitions from: :active, to: :dormant
    end

    # Пробудження після зимового сну / відновлення
    event :reactivate do
      transitions from: :dormant, to: :active
    end

    # Списання дерева (деінсталяція обладнання)
    event :decommission do
      transitions from: [ :active, :dormant ], to: :removed
    end

    # Біологічна смерть дерева
    event :declare_deceased do
      transitions from: [ :active, :dormant ], to: :deceased
    end
  end

  # --- КОНСТАНТИ (Іоністор суперконденсатор 5.5В 0.47Ф) ---
  VCAP_MIN_MV = 2800   # Мінімальна робоча напруга (нижче — STM32 втрачає mesh-relay)
  VCAP_MAX_MV = 5500   # Максимальна напруга повністю зарядженого іоністора
  LOW_POWER_MV = 3300  # Поріг критичного рівня енергії

  # Zero-Trust: Формат DID відповідає апаратній специфікації STM32 (uint32_t → 8 hex digits)
  DID_FORMAT = /\ASNET-[0-9A-F]{8}\z/

  # --- ВАЛІДАЦІЇ ---
  normalize_identifier :did
  validates :did, presence: true, uniqueness: true,
            format: { with: DID_FORMAT, message: "має відповідати апаратному формату (SNET-XXXXXXXX)" }

  # [FW.54/SEC.3] Кремнієвий паспорт (96-біт STM32 UID, три %08X-слова у
  # порядку регістрів): DID деривується з нього (SilkenNet::DidDerivation),
  # а збережений оригінал відрізняє re-flash того самого чипа від
  # birthday-колізії DID двох різних чипів (03_01 §7 → quarantine).
  # nil = legacy-дерево, створене до one-pass провіженінгу.
  normalize_identifier :silicon_uid_hex
  validates :silicon_uid_hex, uniqueness: true, allow_nil: true,
            format: { with: SilkenNet::DidDerivation::UID_HEX_FORMAT, allow_nil: true }

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

  # ⚡ [ГЕОПРОСТОРОВА МАТРИЦЯ]: Оновлюємо вузол на мапі лише при зміні гео-даних або статусу.
  # [ВИПРАВЛЕНО: Broadcast Storm]: Раніше стріляло на КОЖЕН update (включаючи mark_seen!/voltage),
  # що генерувало 10K+ WebSocket-повідомлень/годину при масовій телеметрії.
  # Тепер — тільки при зміні координат, статусу або voltage_mv (UI-релевантні зміни).
  after_update_commit :broadcast_map_update, if: :map_relevant_change?

  # --- СКОУПИ (The Watchers) ---
  # `Tree.active` автогенерується `enum :status, { active: 0, ... }`, не дублюємо.
  scope :geolocated, -> { where.not(latitude: nil, longitude: nil) }

  # [SILENCE-1] Аномальна тиша: active-дерево, що ВЖЕ виходило в ефір, але мовчить
  # довше порога. Поза скоупом свідомо: last_seen_at NULL («мовчання ненародженого» —
  # beginless range робить SQL-відкидання NULL семантикою, не випадковістю), dormant
  # (свідомо приспане) і removed/deceased (легітимно мовчазні — інакше sweeper ганяв би
  # Field Audit на кладовище). Рантайм-поріг веде TreeStalenessSweepWorker через
  # SystemParameter; дефолт 24h [transitional] до bench-калібрування (00_07 SILENCE-1:
  # delta_t навмисно варіативний, поріг НЕ виводиться з конфіга). Стеля: індексу на
  # last_seen_at нема — на тисячах рядків seq-scan дешевий, scale → індекс.
  scope :silent, ->(threshold = 24.hours) { active.where(last_seen_at: ...threshold.ago) }
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
    # [ВИПРАВЛЕНО: Broadcast Storm]: Видалено broadcast_map_update з hot path телеметрії.
    # mark_seen! викликається для КОЖНОГО пакету (мільйони на годину).
    # Мапа оновлюється через after_update_commit :broadcast_map_update лише при
    # зміні координат або статусу (map_relevant_change?).
  end

  # Останній вердикт Оракула
  # [ВИПРАВЛЕНО: N+1 TreeBlueprint#current_stress]:
  # Тепер читаємо денормалізовану колонку latest_stress_index замість запиту до ai_insights.
  # Колонка оновлюється InsightGeneratorService при щоденній агрегації.
  # Це усуває N+1 запит для КОЖНОГО дерева при серіалізації TreeBlueprint :index та Dashboard::MapNode.
  def current_stress
    latest_stress_index.to_f
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
  def latest_telemetry_log
    @latest_telemetry_log ||= telemetry_logs.order(created_at: :desc).first
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

  # [FW.8] Effective Lorenz thresholds with three-level priority chain (governance):
  #   1. Cluster-level per-species override (cluster.lorenz_overrides_for(scientific_name))
  #      — a cluster may host trees of several species; each species gets its own
  #        biome-adjusted overrides set by org admin.
  #   2. TreeFamily per-species value
  #   3. Global default (BioContract::CRITICAL_Z_MIN/MAX/OPTIMAL_Z_TARGET)
  #
  # Returns Hash{ min:, max:, optimal: } of Float values.
  # SSOT consumed by:
  #   - TelemetryUnpackerService for Z divergence checks
  #   - OtaPackagerService when emitting CMD_SET_THRESHOLDS (0x9A) to Soldier
  def effective_lorenz_thresholds
    family    = tree_family
    overrides = cluster && family&.scientific_name ? cluster.lorenz_overrides_for(family.scientific_name) : {}

    {
      min:     overrides[:min]     || family&.critical_z_min&.to_f || GLOBAL_LORENZ_Z_MIN,
      max:     overrides[:max]     || family&.critical_z_max&.to_f || GLOBAL_LORENZ_Z_MAX,
      optimal: overrides[:optimal] || family&.effective_optimal_z_target || GLOBAL_LORENZ_Z_OPTIMAL
    }
  end

  private

  # [ВИПРАВЛЕНО: Broadcast Storm]: Визначаємо, чи зміна є релевантною для оновлення мапи.
  # Широкомовлення лише при зміні координат, статусу або latest_voltage_mv (іконка батареї).
  # Це скорочує кількість WebSocket-повідомлень з ~10K/годину до ~100/годину.
  def map_relevant_change?
    saved_change_to_latitude? || saved_change_to_longitude? ||
      saved_change_to_status? || saved_change_to_latest_voltage_mv?
  end

  def build_default_wallet
    create_wallet!(balance: 0, organization: cluster&.organization)
  end

  def ensure_calibration
    create_device_calibration! unless device_calibration
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

  # Counter cache sync на cluster.active_trees_count. Покриває всі дельти:
  #   * status change (active ↔ dormant/removed/deceased) → swap counter same cluster
  #   * cluster change на active tree → decrement old, increment new
  #   * both change → decrement old, conditionally increment new
  #   * cluster: nil → A → increment A (after_create_commit handles initial set)
  # `saved_change_to_*` повертає `[before, after]` коли поле змінилось,
  # nil — якщо без змін. Прямо використовуємо before-значення замість
  # ручного fallback на `*_before_type_cast` (Rails enum віддавав би
  # integer там, де AASM/saved_change віддає string — старий шлях мав
  # подвійний `|| 0` workaround).
  def update_cluster_active_trees_count
    was_active =
      if saved_change_to_status?
        saved_change_to_status.first == "active"
      else
        active?
      end

    old_cluster_id =
      if saved_change_to_cluster_id?
        saved_change_to_cluster_id.first
      else
        cluster_id
      end

    # Декремент: дерево було активним і прив'язаним до кластера.
    if was_active && old_cluster_id
      Cluster
        .where(id: old_cluster_id)
        .where("active_trees_count > 0")
        .update_all("active_trees_count = active_trees_count - 1")
    end

    # Інкремент: дерево зараз активне і прив'язане до кластера.
    if active? && cluster_id
      Cluster
        .where(id: cluster_id)
        .update_all("active_trees_count = active_trees_count + 1")
    end
  end
end
