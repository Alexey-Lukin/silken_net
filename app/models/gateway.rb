# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class Gateway < ApplicationRecord
  include AASM
  include Firmwareable
  include GeoLocatable
  include NormalizeIdentifier

  # Polymorphic identifier для UI/serializers (див. Tree#display_identifier).
  alias_attribute :display_identifier, :uid

  # --- ЗВ'ЯЗКИ (The Fabric of the Forest) ---
  belongs_to :cluster

  # Zero-Trust: Унікальний ключ для розшифровки батчів (DID Королеви = device_uid ключа)
  has_one :hardware_key, foreign_key: :device_uid, primary_key: :uid, dependent: :destroy

  # Дерева в секторі (через кластер) — використовується у вьюхах для відображення підлеглих
  has_many :trees, through: :cluster

  # Телеметрія дерев та власна діагностика Королеви
  has_many :telemetry_logs, foreign_key: :queen_uid, primary_key: :uid, dependent: :nullify
  has_many :gateway_telemetry_logs, foreign_key: :queen_uid, primary_key: :uid, dependent: :delete_all
  # rubocop:disable Rails/HasManyOrHasOneDependent -- це READ-проєкція «останній
  # рядок», а не володіння: знищенням журналу відає сусідній
  # `has_many :gateway_telemetry_logs, dependent: :delete_all`. `dependent:` тут
  # означав би «знести лише найсвіжіший запис», що не є ніяким наміром.
  has_one :latest_gateway_telemetry_log, -> { order(created_at: :desc) },
          class_name: "GatewayTelemetryLog", foreign_key: :queen_uid, primary_key: :uid
  # rubocop:enable Rails/HasManyOrHasOneDependent

  # [ВИПРАВЛЕНО]: Знищення Журналу Обслуговування (Аудит).
  # Використовуємо :restrict_with_error, щоб зберегти історію витрат та ремонтів.
  #
  # ⚠️ Тут стояло «Королеву можна списати (`status: :retired`)» — такого стану НЕМАЄ:
  # `state` несе лише операційні значення (`idle`/`active`/`updating`/`maintenance`/
  # `faulty`), і петля між ними замкнена без точки виходу. У Дерева життєвий цикл є
  # (AASM `decommission!` → `removed`), у Королеви — ні, і `EcosystemHealingWorker`
  # гейтує ту гілку на `target.is_a?(Tree)`, тож `MaintenanceRecord(decommissioning)`
  # на шлюз створюється, валідується й НЕ РОБИТЬ НІЧОГО — журнал стверджує дію, якої
  # не сталося. Потрібен один термінальний trust-revocation стан (вкрадена Королева
  # тримає у флеші CoAP-ключ, QATT-seed і KEYB усього кластера, а Dual-Key Grace без
  # фізичного re-provision не гасне ніколи) → `00_07` ARCH.76.
  has_many :maintenance_records, as: :maintainable, dependent: :restrict_with_error

  has_many :actuators, dependent: :destroy
  has_many :actuator_commands, through: :actuators

  # --- СТАНИ (The Sovereign States) ---
  enum :state, {
    idle: 0,        # Очікування / Сон
    active: 1,      # Передача телеметрії
    updating: 2,    # Прийом OTA чанків (Busy)
    maintenance: 3, # Технічне обслуговування
    faulty: 4       # Апаратний збій / вичерпано ретраї OTA
  }, default: :idle

  # =========================================================================
  # ЖИТТЄВИЙ ЦИКЛ ШЛЮЗУ (AASM State Machine)
  # =========================================================================
  aasm column: :state, enum: true, whiny_persistence: true do
    state :idle, initial: true
    state :active
    state :updating
    state :maintenance
    state :faulty

    # Шлюз активно передає телеметрію
    event :wake do
      transitions from: :idle, to: :active
    end

    # Повернення в режим сну
    event :sleep do
      transitions from: :active, to: :idle
    end

    # Початок OTA оновлення
    event :begin_update do
      transitions from: [ :idle, :active ], to: :updating
    end

    # Завершення OTA (повернення в idle)
    event :finish_update do
      transitions from: :updating, to: :idle
    end

    # Перехід у режим обслуговування
    event :enter_maintenance do
      transitions from: [ :idle, :active, :faulty ], to: :maintenance
    end

    # Повернення з обслуговування
    event :exit_maintenance do
      transitions from: :maintenance, to: :idle
    end

    # Апаратний збій
    event :report_fault do
      transitions from: [ :idle, :active, :updating, :maintenance ], to: :faulty
    end

    # [ARCH.54 Шар 0] Повернення в ефір після faulty: sweeper бачить свіжий
    # last_seen_at і повертає шлюз у стрій (idle — wake підніме в active).
    event :recover do
      transitions from: :faulty, to: :idle
    end
  end

  # --- КОНСТАНТИ ---
  # Zero-Trust: Формат UID відповідає апаратній специфікації шлюзу (SNET-Q-[8 hex digits])
  UID_FORMAT = /\ASNET-Q-[0-9A-F]{8}\z/
  LOW_POWER_MV = 3300  # Поріг критичного рівня енергії (аналогічно Tree::LOW_POWER_MV)

  # --- КОЛБЕКИ ТА ВАЛІДАЦІЇ ---
  normalize_identifier :uid

  validates :uid, presence: true, uniqueness: true,
            format: { with: UID_FORMAT, message: :must_match_hardware_format }
  validates :config_sleep_interval_s, presence: true, numericality: { greater_than_or_equal_to: 60 }

  # IP адреса модему SIM7070G (Starlink/LTE)
  validates :ip_address, format: { with: Resolv::AddressRegex }, allow_blank: true

  # --- СКОУПИ (The Watchers) ---
  # [ВИПРАВЛЕНО]: Індексоване обчислення порогу (make_interval замість string-concat).
  #
  # 🔴 [ARCH.115, ⚖️ 2026-08-29] БАЗУ ЗМІНЕНО: вікно рахується від ВИМІРЯНОГО каденсу
  # прошивки, а не від колонки `config_sleep_interval_s`. Підстава — не стиль:
  # **`grep sleep_interval firmware/` дає НУЛЬ.** Прошивка тієї колонки не читає взагалі,
  # і downlink'а, який доніс би її до Королеви, не існує; реальний каденс зашитий
  # компайл-тайм таймером `FLUSH_INTERVAL_MS` (3 600 000) + jitter (60 000). Тобто шлюз,
  # провіжінений на 3600, і шлюз на 300 флашать ОДНАКОВО — колонка була Rails-side
  # переконанням про пристрій, а не його поведінкою.
  #
  # 🔑 Присуд уже стояв У СУСІДНЬОМУ ДОМІ й просто не доїхав сюди: `Downlink::
  # PendingQueueService::WORST_CASE_POLL_INTERVAL_S` несе той самий вимір із тим самим
  # обґрунтуванням, бо там питали «чи встигне downlink». Питання «чи живий шлюз» жило
  # в іншому домі, і вимір туди не поїхав — саме тому тут стоїть ОДНЕ джерело на обидва.
  #
  # ⚠️ Люфт 20% лишається як був — змінилась ЛИШЕ база. Наслідок треба знати обома
  # боками: для прод-дефолту (3600) вікно ЗВУЖУЄТЬСЯ 4320 → 4392 с майже без змін, а для
  # сідового шлюзу (1800) РОЗШИРЮЄТЬСЯ 2160 → 4392, і саме там жив дефект — здорова
  # Королева ~25 хв щогодини числилась `offline`, що давало хибний critical `queen_offline`,
  # виключало її з `ota_deployable` і робило `EmergencyResponseService.deliverable?`
  # хибним на пожежному протоколі.
  # ⛔ Не повертати колонку в цей вираз, доки прошивка її не читає: спершу downlink-тракт
  # доставки конфігу, і аж тоді вона стає ВИМІРОМ, а не переконанням.
  LIVENESS_WINDOW_S = (Downlink::PendingQueueService::WORST_CASE_POLL_INTERVAL_S * 1.2).round

  scope :online, -> {
    where("last_seen_at >= CURRENT_TIMESTAMP - make_interval(secs => ?)", LIVENESS_WINDOW_S)
  }

  scope :offline, -> {
    where("last_seen_at IS NULL OR last_seen_at < CURRENT_TIMESTAMP - make_interval(secs => ?)", LIVENESS_WINDOW_S)
  }

  scope :ready_for_commands, -> { idle.online }

  # [SEC.20] Придатний для OTA-кампанії: є куди слати (ip) + не в сервісних
  # станах + НЕ у своїй кампанії (updating): Queen тримає один глобальний
  # OTA-буфер без campaign-id — перекриті кампанії = битий образ в ефірі.
  # Ширший за best_gateway_for downlink-воркерів рівно на :updating
  # (одиночна дейтаграма кампанії не боїться).
  scope :ota_deployable, -> {
    where.not(ip_address: [ nil, "" ]).where.not(state: %w[maintenance faulty updating])
  }

  # --- МЕТОДИ (Intelligence) ---

  # [ВИПРАВЛЕНО: Race Condition + Performance]:
  # GREATEST гарантує детермінованість при дубльованих пакетах через Starlink Direct to Cell.
  # update_all обходить колбеки ActiveRecord — блискавичне оновлення на hot path телеметрії.
  def mark_seen!(new_ip: nil, voltage_mv: nil)
    now = Time.current

    set_clauses = [ "last_seen_at = GREATEST(COALESCE(last_seen_at, ?), ?)" ]
    bind_values = [ now, now ]

    if new_ip.present?
      set_clauses << "ip_address = ?"
      bind_values << new_ip
    end

    if voltage_mv.present?
      set_clauses << "latest_voltage_mv = ?"
      bind_values << voltage_mv
    end

    self.class.where(id: id).update_all([ set_clauses.join(", "), *bind_values ])

    # Синхронізуємо in-memory стан без reload для швидкодії на hot path
    self.last_seen_at = now
    self.ip_address = new_ip if new_ip.present?
    self.latest_voltage_mv = voltage_mv if voltage_mv.present?
  end

  # [ARCH.115] Те саме вікно, що в скоупах `online`/`offline` — і спільна константа тут
  # несуча, а не охайність: предикат і скоуп відповідають на ОДНЕ питання, тож
  # розходження між ними давало б рядок, видимий у списку й «мертвий» у деталці.
  def online?
    return false if last_seen_at.nil?

    last_seen_at >= LIVENESS_WINDOW_S.seconds.ago
  end

  # Розрахунок наступного вікна зв'язку (Projected Pulse)
  def next_wakeup_expected_at
    last_seen_at ? last_seen_at + config_sleep_interval_s.seconds : nil
  end

  # Чи потребує Королева уваги патрульного?
  def system_fault?
    # [SLASH-1 2026-09-04] Родина, не один тип: кошик `system_fault` розколюється
    # за атрибуцією, а це питання про ВИДИМІСТЬ — див. `EwsAlert::GATEWAY_FAULT_TYPES`.
    cluster&.ews_alerts&.unresolved&.where(alert_type: EwsAlert::GATEWAY_FAULT_TYPES)&.exists? ||
      battery_critical?
  end

  # [ВИПРАВЛЕНО]: Блискавична перевірка без SQL запитів до логів.
  # Використовуємо денормалізовану колонку latest_voltage_mv.
  # ⚠️ [ARCH.99] СТЕЛЯ, названа явно: гілка сьогодні НЕ виконується — писача
  # колонки не існує (`GatewayTelemetryWorker`: «пульс v2 напруги не несе — нема
  # ADC»), тож `.present?` завжди хибний і `system_fault?` зводиться до перевірки
  # алертів. Це fail-closed у безпечний бік і свідомо: предикат чекає залізного
  # тракту, а не мертвий. ⊥ НЕ те саме, що зняте у Tree: там величину міряли й
  # вона не могла відповісти на питання, тут її просто ще не міряють.
  # Живий сигнал стану шлюза доти — тиша: `Gateway.offline` +
  # `GatewayStalenessSweepWorker` (dead-man switch, `06_08 §1.3`).
  def battery_critical?
    latest_voltage_mv.present? && latest_voltage_mv < LOW_POWER_MV
  end
end
