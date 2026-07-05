# frozen_string_literal: true

class TelemetryLog < ApplicationRecord
  # --- ЗВ'ЯЗКИ (The Neural Links) ---
  belongs_to :tree
  # Зв'язок із Королевою через її UID
  belongs_to :gateway, foreign_key: :queen_uid, primary_key: :uid, optional: true
  # [E.62-патерн — mis-join trap, асоціація вимкнена]:
  # `firmware_version_id` зберігає WIRE-ідентифікатор прошивки (21B: uint16 з
  # PAD-байтів; CCM: 4-бітний epoch-нібл verbatim — стопгеп до OTA epoch config),
  # а НЕ автоінкрементний `bio_contract_firmwares.id`. belongs_to по цій колонці
  # повертав би чужий запис, щойно в таблиці з'являться рядки з малими id.
  # Реальний трекінг версій — SemVer-рядки (`Tree.firmware_version`), див.
  # коментар E.62 у `BioContractFirmware`. Розкоментовувати лише разом із
  # канонізованим мапінгом wire-id ↔ запис.
  # belongs_to :bio_contract_firmware, foreign_key: :firmware_version_id, optional: true

  # --- СТАТУСИ (The Pulse of Life) ---
  # [SLASH-1] Wire-код 3 пише ВИКЛЮЧНО BIO_STATUS_VM_ERROR (0x60, firmware/soldier/main.c):
  # mruby-crash / VM-OOM / unprovisioned. mruby pack_status_byte повертає лише 0..2;
  # фізичний tamper (п'єзо → TinyML chainsaw) їде PANIC_FLAG-каналом (FW.29), НЕ статусом.
  # Стара назва tamper_detected інвертувала semantics: софт-збій читався «вандалізмом»
  # (positive-A slash жертви OTA-бага), а справжня пилка в A-сет не потрапляла.
  enum :bio_status, {
    homeostasis: 0,      # Здоровий Хаос (Атрактор у нормі)
    stress: 1,           # Раннє попередження (Посуха)
    anomaly: 2,          # Критичний збій / Хвороба
    vm_error: 3          # Софт-збій прошивки (mruby VM / unprovisioned) — НЕ tamper
  }, prefix: true

  # [BLOCKER-12 FIX]: Enum для oracle_status замість plain string.
  # Забезпечує type safety, Rails-level валідацію та автоматичні scope-методи.
  enum :oracle_status, {
    pending: "pending",
    dispatched: "dispatched",
    fulfilled: "fulfilled",
    failed: "failed"
  }, prefix: true

  # --- КЛІМАТ (BME280, HW.32 — ADR 02_01 §3.4) ---
  # humidity (% RH), pressure (hPa), vpd (kPa) — усі nullable/sparse: hot-path шле
  # лише VPD-індекс, raw RH/тиск приходять у періодичному climate frame. `vpd` —
  # прямий confounder сокоруху (False-Slashing guard, 05_05 §7).
  # ⚠️ DCI-guard: жодне з цих НЕ входить у Lorenz-Z (firmware↔backend bit-identity).

  # --- ВАЛІДАЦІЇ ---
  # [KENOSIS TITAN]: Валідації видалено з hot path.
  # На Series C/D масштабі (мільйони пакетів/хв) дані перевіряються
  # в TelemetryUnpackerService.valid_sensor_data? до створення запису.
  # ActiveRecord валідації на кожному INSERT — зайві цикли CPU.

  # --- ПОРОГИ АНАЛІТИКИ (канон значень — тут, 04_01 дзеркалить) ---
  # Акустика: < CALM_MAX — здорова тиша; > STORM_MIN — шторм (шкідники/пилка).
  # Сіра зона CALM_MAX..STORM_MIN навмисна: «навантажено, але ще не аномалія».
  ACOUSTIC_CALM_MAX  = 20
  ACOUSTIC_STORM_MIN = 50
  HEALTHY_TEMP_MAX_C = 50

  # --- СКОУПИ (The Analytical Eyes) ---
  # Індекс: index_telemetry_logs_on_tree_id_and_created_at
  scope :recent, -> { order(created_at: :desc) }

  # [S6.16] Partition pruning з ISO-8601 рядка для RANGE-партиційованої
  # таблиці; chainable: `TelemetryLog.where(...).partition_pruned(iso, ...)`.
  # Єдиний дім pruning-логіки — воркери/сервіси/контролери НЕ дублюють.
  # Вікно в 1 секунду — толерантне до секундної точності ISO проти
  # мікросекундних DB-timestamps (стандарт `BlockchainTransaction`);
  # PostgreSQL все одно прунить до однієї партиції.
  # Degraded path (відсутній/битий created_at_iso) → сканування всіх
  # партицій O(P×log N) — облікований лічильником unpruned_lookups.
  def self.partition_pruned(created_at_iso, metric_caller:)
    if created_at_iso.blank?
      SilkenNet::Metrics::TELEMETRY_LOG_UNPRUNED_LOOKUPS_TOTAL
        .increment(labels: { caller: "#{metric_caller}:missing_created_at_iso" })
      return all
    end

    time = Time.iso8601(created_at_iso)
    where(created_at: time...(time + 1))
  rescue ArgumentError, TypeError
    Rails.logger.warn "⚠️ [S6.16] #{metric_caller}: битий created_at_iso #{created_at_iso.inspect} — lookup без partition pruning."
    SilkenNet::Metrics::TELEMETRY_LOG_UNPRUNED_LOOKUPS_TOTAL
      .increment(labels: { caller: "#{metric_caller}:invalid_iso8601" })
    all
  end

  # Індекс: idx_telemetry_logs_bio_status_created
  scope :anomalies, -> {
    where(bio_status: [ :stress, :anomaly, :vm_error ])
    .or(where("acoustic_events > ?", ACOUSTIC_STORM_MIN))
  }

  scope :in_timeframe, ->(start_time, end_time) { where(created_at: start_time..end_time) }

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
    bio_status_anomaly? || bio_status_vm_error?
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
      temperature_c.present? && temperature_c < HEALTHY_TEMP_MAX_C &&
      acoustic_events.present? && acoustic_events < ACOUSTIC_CALM_MAX
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
