# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class TelemetryLog < ApplicationRecord
  # PostgreSQL PK is composite (id, created_at) for declarative partitioning,
  # but Rails should use id alone for lookups, dom_id, and associations —
  # otherwise record.id returns [id, created_at] (дзеркало BlockchainTransaction).
  self.primary_key = "id"

  # --- ЗВ'ЯЗКИ (The Neural Links) ---
  belongs_to :tree
  # Зв'язок із Королевою через її UID
  belongs_to :gateway, foreign_key: :queen_uid, primary_key: :uid, optional: true
  # [E.62-патерн — mis-join trap, асоціація вимкнена]:
  # `firmware_version_id` зберігає WIRE-звіт прошивки, а НЕ чистий
  # `bio_contract_firmwares.id`. Post-SEC.20 семантика (firmware/common/fw_report.h):
  # semantic-біт → [reverted:1 | contract_id&0x3FFF] (id ПО МОДУЛЮ 14 біт —
  # звіряй через firmware_report_contract_id, не join); без semantic-біта —
  # legacy C-image константа (стара прошивка), contract-версії НЕ несе.
  # belongs_to по цій колонці повертав би чужий запис — трекінг через
  # хелпери нижче + SemVer-рядки (`Tree.firmware_version`, E.62).
  # belongs_to :bio_contract_firmware, foreign_key: :firmware_version_id, optional: true

  # [SEC.20] Дзеркало fw_report.h — wire-звіт contract-стану (байти 12..13
  # legacy / vpd-байт CCM, unpacker складає у спільні 16 біт).
  FW_REPORT_SEMANTIC_BIT = 0x8000
  FW_REPORT_REVERTED_BIT = 0x4000
  FW_REPORT_ID_MASK      = 0x3FFF

  # Звіт нової семантики? (legacy-прошивки шлють C-image константу без біта)
  def firmware_report_semantic?
    firmware_version_id.to_i.anybits?(FW_REPORT_SEMANTIC_BIT)
  end

  # Вузол біжить embedded baseline ПРИ спаленому OTA-припливі — сигнатура
  # auto-fallback (SEC.20): термінальний стан до re-issue версії > спаленої.
  def firmware_report_reverted?
    firmware_report_semantic? && firmware_version_id.to_i.anybits?(FW_REPORT_REVERTED_BIT)
  end

  # Contract-id по модулю 14 біт (nil для legacy-кадрів).
  def firmware_report_contract_id
    return nil unless firmware_report_semantic?
    firmware_version_id.to_i & FW_REPORT_ID_MASK
  end

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

  # [E.60 Фаза 1б] Seal-guard стемпнутого листа: merkle_leaf = персистований CID
  # leaf-payload'а (Mrv::TelemetryLeaf); мутація payload-поля після стемпу зламала б
  # відповідність лист ↔ запінений артефакт ↔ on-chain root. Свідома пара захистів:
  # guard тримає AR-шлях (update/save), sweeper-нога FilecoinVerificationSweepWorker
  # ловить raw-SQL-шлях семпл-перерахунком CID. Сам стемп пише pin-воркер raw-SQL'ем
  # (колбек не стріляє) і nil→value проходить guard (merkle_leaf_was порожній).
  # KENOSIS недоторканий: intake = insert_all, before_update на INSERT не стріляє.
  # Прецедент: AuditLog#forbid_business_field_mutation! (ARCH.57).
  LEAF_PAYLOAD_COLUMNS = %w[z_value bio_status created_at tree_id].freeze
  before_update :forbid_sealed_leaf_mutation!

  # --- ПОРОГИ АНАЛІТИКИ (канон значень — тут, 04_01 дзеркалить) ---
  # Акустика: > STORM_MIN — шторм (кавітація/пилка над порогом confidence).
  # ⛔ [ARCH.84] `ACOUSTIC_CALM_MAX` (20) і `HEALTHY_TEMP_MAX_C` (50) знято разом
  # із `healthy?` — обидва були bootstrap-числами того самого коміту 2026-03-02,
  # без калібрувального сліду. Новіший код тієї ж платформи вже так не робить:
  # acoustic-term у `InsightGeneratorService` ІНЕРТНИЙ, доки поріг не заданий
  # ground-truth'ом («no guessed count in live slashing»).
  ACOUSTIC_STORM_MIN = 50

  # --- СКОУПИ (The Analytical Eyes) ---
  # Індекс: index_telemetry_logs_on_tree_id_and_created_at
  scope :recent, -> { order(created_at: :desc) }

  # [PERF.1] Останній рядок на КОЖНЕ дерево набору — ОДИН `DISTINCT ON` замість
  # N окремих `ORDER BY created_at DESC LIMIT 1`. Дім саме тут, бо `Tree#latest_telemetry_log`
  # відповідає на це питання для ОДНОГО дерева й у циклі вироджується в N+1.
  #
  # 🔒 **Стеля названа, бо інакше зелений план читався б як «запруніли»:** межі по
  # `created_at` тут НЕМАЄ і бути не може — питання саме́ звучить «останній, хоч би
  # коли він був», тож будь-яке вікно ЗМІНИЛО Б ВІДПОВІДЬ (дерево, що мовчить довше
  # вікна, віддало б порожньо замість останнього відомого рядка). Це рівно та пастка,
  # на якій PERF.1 уже спіткнувся з `2.months` у `previous_lorenz_state_for`. Отже
  # виграш тут — у КІЛЬКОСТІ запитів (N → 1), а не в обсязі скану: партиції
  # проходяться всі, як і доти. Дешевший план потребує іншої форми — денормалізованого
  # вказівника на Дереві (дзеркало `latest_stress_index`), і це окреме рішення з
  # власною ціною (старіння писача, `00_07` PERF.1 кандидат «а»).
  scope :latest_per_tree, ->(tree_ids) {
    where(tree_id: tree_ids).select("DISTINCT ON (tree_id) *").order(:tree_id, created_at: :desc)
  }

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

    # `Time.zone.iso8601`, ніколи голий `Time.iso8601` [ARCH.92]: другий читає зону
    # ПРОЦЕСУ, тож рядок без суфікса зони (їх виробляє зовнішній JS оракула, не наші
    # серіалізатори) зсував би вікно на UTC-офсет хоста — а вікно тут секундне, тож
    # промах тихо повертає ПОРОЖНЬО замість запису.
    #
    # ⚠️ Гард на час несучий: `Time.zone.iso8601` приймає дату-без-часу (`2026-05-23`
    # → північ), і без нього такий вхід дав би секундне вікно навколо 00:00:00
    # замість чесного fallback'у — тобто «не знайшли» замість «шукали без прунінгу».
    raise ArgumentError, "created_at_iso without a time component" unless created_at_iso.to_s.include?("T")

    time = Time.zone.iso8601(created_at_iso)
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

  # ⛔ [ARCH.84, ⚖️ присуд founder 2026-08-16] Anti-flapping-петлю знято ЦІЛКОМ:
  # `healthy?` · `optimal?` · `recovery_confirmed?` · `OPTIMAL_Z_BAND` ·
  # `HEALTHY_TEMP_MAX_C` · `ACOUSTIC_CALM_MAX` + колонка `trees.health_streak`
  # + писач `TelemetryUnpackerService#update_health_streak!`.
  #
  # 🔴 Підстава — НЕ «нуль читачів»: продакшну не було, тож це вимір
  # недобудованості, а не смерті. Знято тому, що КОНСТРУКЦІЯ хибна — сигнал
  # закриття не спростовує сигнал відкриття:
  #   · `severe_drought` народжується ДВОМА гілками (пристрійний `z < 2.0` АБО
  #     серверний `Attractor.homeostatic?` поза per-family смугою), а `healthy?`
  #     другу не перевіряв ЖОДНОГО разу — для родини з `critical_z_min > 2.0`
  #     стрік ріс, ПОКИ причина тривоги тривала;
  #   · `entropy_anomaly` — інший рівень агрегації: Shannon по кластеру за добу
  #     проти трьох пакетів одного дерева.
  # ⊕ Каденс Солдата енергетичний, не календарний: «3 пакети» = від ~2 хв до
  # 2+ діб, і вікно розтягується САМЕ тоді, коли дерево хворе (EBFC живиться
  # соком). Плюс sentinel-нуль [ARCH.41-B] фабрикував «спокійні» пакети, які
  # інкрементували лічильник.
  # ⚠️ Не відроджувати як «майже готову фічу»: канон уже призначив суддею
  # ЛЮДИНУ (`05_05` INS.1 — drought/pest-оракула не існує), а активна біо-тривога
  # є ВОРОТАМИ перед незворотною страховою виплатою. Прецедент форми дослівний —
  # `EwsAlert` `actuator_stuck`: «Машинного resolve НЕМА свідомо».
  # Повний розбір і чотири рамки виміру → `00_07` ARCH.84.

  private

  # [E.60] Дзеркало AuditLog#forbid_business_field_mutation! — детальніше біля
  # LEAF_PAYLOAD_COLUMNS вище.
  def forbid_sealed_leaf_mutation!
    return if merkle_leaf_was.blank?

    illegal = changed & LEAF_PAYLOAD_COLUMNS
    return if illegal.empty?

    raise ActiveRecord::ReadOnlyRecord,
          "TelemetryLog ##{id}: sealed leaf [E.60] — спроба змінити #{illegal.join(', ')}"
  end
end
