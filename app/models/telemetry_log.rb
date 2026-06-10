# frozen_string_literal: true

class TelemetryLog < ApplicationRecord
  # --- ЗВ'ЯЗКИ (The Neural Links) ---
  belongs_to :tree
  # Зв'язок із Королевою через її UID
  belongs_to :gateway, foreign_key: :queen_uid, primary_key: :uid, optional: true
  # Трекінг версії прошивки (з 4 байтів padding-у)
  belongs_to :bio_contract_firmware, foreign_key: :firmware_version_id, optional: true

  # --- СТАТУСИ (The Pulse of Life) ---
  # [СИНХРОНІЗОВАНО]: Додано tamper_detected для відповідності сервісам
  enum :bio_status, {
    homeostasis: 0,      # Здоровий Хаос (Атрактор у нормі)
    stress: 1,           # Раннє попередження (Посуха)
    anomaly: 2,          # Критичний збій / Хвороба
    tamper_detected: 3   # Вандалізм / Розкриття корпусу
  }, prefix: true

  # [BLOCKER-12 FIX]: Enum для oracle_status замість plain string.
  # Забезпечує type safety, Rails-level валідацію та автоматичні scope-методи.
  enum :oracle_status, {
    pending: "pending",
    dispatched: "dispatched",
    fulfilled: "fulfilled",
    failed: "failed"
  }, prefix: true

  # --- КЛІМАТ (BME280, HW.20 — ADR 02_01 §3.4) ---
  # humidity (% RH), pressure (hPa), vpd (kPa) — усі nullable/sparse: hot-path шле
  # лише VPD-індекс, raw RH/тиск приходять у періодичному climate frame. `vpd` —
  # прямий confounder сокоруху (False-Slashing guard, 00_01 §6.5/§6.6).
  # ⚠️ DCI-guard: жодне з цих НЕ входить у Lorenz-Z (firmware↔backend bit-identity).

  # --- ВАЛІДАЦІЇ ---
  # [KENOSIS TITAN]: Валідації видалено з hot path.
  # На Series C/D масштабі (мільйони пакетів/хв) дані перевіряються
  # в TelemetryUnpackerService.valid_sensor_data? до створення запису.
  # ActiveRecord валідації на кожному INSERT — зайві цикли CPU.

  # --- СКОУПИ (The Analytical Eyes) ---
  # Індекс: index_telemetry_logs_on_tree_id_and_created_at
  scope :recent, -> { order(created_at: :desc) }

  # Partition-aware lookup for RANGE-partitioned telemetry_logs.
  # Workers pass created_at_iso to enable PostgreSQL to scan only the relevant
  # partition (O(log N)) instead of all partitions (O(P×log N)).
  def self.find_with_partition_pruning(id, created_at = nil)
    scope = where(id: id)
    if created_at.present?
      time = created_at.is_a?(String) ? Time.iso8601(created_at) : created_at.to_time
      scope = scope.where(created_at: time...(time + 1))
    end
    scope.first!
  rescue ArgumentError, TypeError, NoMethodError
    where(id: id).first!
  end

  # Індекс: idx_telemetry_logs_bio_status_created
  scope :anomalies, -> {
    where(bio_status: [ :stress, :anomaly, :tamper_detected ])
    .or(where("acoustic_events > ?", 50))
  }

  scope :in_timeframe, ->(start_time, end_time) { where(created_at: start_time..end_time) }

  # [ВИПРАВЛЕНО]: Використовуємо енум замість окремої колонки
  scope :vandalized, -> { bio_status_tamper_detected }

  # Індекс: idx_telemetry_logs_piezo_created
  scope :seismic_activity, -> { where("piezo_voltage_mv > ?", 1500) }

  # --- МЕТОДИ (Topology Analysis) ---

  # Стартовий TTL пакета на дроті — дзеркало firmware/soldier/main.c
  # (DEFAULT_TTL / PANIC_TTL); значення правити там, тут лише читати.
  INITIAL_TTL_NORMAL = 3
  INITIAL_TTL_PANIC  = 5

  # Чи пройшов пакет через Mesh-ретрансляцію інших дерев: кожен hop
  # декрементує TTL, тож прибуття з TTL нижче стартового = релей.
  # Стартовий TTL залежить від типу пакета — звичайний народжується з 3,
  # панічний з 5 (panic персиститься з PanicFlag StatusByte, FW.29).
  def relayed_via_mesh?
    mesh_ttl < (panic? ? INITIAL_TTL_PANIC : INITIAL_TTL_NORMAL)
  end

  # Швидка перевірка на критичність для UI
  def critical?
    bio_status_anomaly? || bio_status_tamper_detected?
  end

  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  # SELF-HEALING INTELLIGENCE (Recovery Protocols)
  # = :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

  # Дерево вважається здоровим, якщо воно в гомеостазі,
  # температура в межах норми і немає акустичного шторму шкідників.
  # nil-safe: на hot path TelemetryLog може мати nil-fields коли запис
  # створюється через insert_all (KENOSIS TITAN bypass валідацій).
  def healthy?
    bio_status_homeostasis? &&
      temperature_c.present? && temperature_c < 50 &&
      acoustic_events.present? && acoustic_events < 20
  end

  # "Optimal" стан Lorenz attractor: Z поряд із OPTIMAL_Z_TARGET (29.0).
  # SSOT — `BioContract::OPTIMAL_Z_TARGET` (firmware) / `Tree::GLOBAL_LORENZ_Z_OPTIMAL`.
  # Раніше використовував діапазон 0.1..0.5, що було залишком до-FW.8 нормалізації
  # і ніколи не співпадало з реальними значеннями Z (2.0..45.0).
  OPTIMAL_Z_BAND = 4.0

  def optimal?
    return false unless healthy?
    return false unless voltage_mv.present? && voltage_mv > 3600
    return false unless z_value.present?

    target = Tree::GLOBAL_LORENZ_Z_OPTIMAL
    (z_value.to_f - target).abs <= OPTIMAL_Z_BAND
  end

  # [KENOSIS TITAN]: Перевірка на "Відновлення" (Anti-Flapping)
  # Використовується в AlertDispatchService для автоматичного закриття тривог.
  # Замість N+1 запиту tree.telemetry_logs.recent.limit(3) — використовуємо
  # денормалізований лічильник health_streak з моделі Tree.
  # Лічильник оновлюється атомарно в TelemetryUnpackerService.commit_telemetry.
  def recovery_confirmed?
    return false unless healthy?

    tree.health_streak >= 3
  end
end
