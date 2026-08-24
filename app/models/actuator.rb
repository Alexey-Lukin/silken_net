# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class Actuator < ApplicationRecord
  include AASM

  # --- ЗВ'ЯЗКИ ---
  belongs_to :gateway
  has_one :cluster, through: :gateway
  # [BLOCKER FIX: Чорна Діра Пам'яті]: Замінено :destroy на :delete_all.
  # :destroy завантажував кожен ActuatorCommand у Ruby та запускав AASM-колбеки,
  # Turbo broadcast і sidekiq-jobs при видаленні шлюзу. При 1000+ команд на
  # актуатор це призводило б до OOM. delete_all виконує один SQL DELETE.
  # ActuatorCommand не має фінансових зобов'язань, тому bypass callbacks безпечний.
  has_many :commands, class_name: "ActuatorCommand", dependent: :delete_all

  # --- ТИПИ ПРИСТРОЇВ (The Arsenal) ---
  #
  # ⚠️ Диспетчеризує рід пристрою РІВНО одна таблиця — `EmergencyResponseService::PROTOCOLS`,
  # і сьогодні вона знає лише перші два. Решта — ОГОЛОШЕНІ forward-контракти, а не забуті
  # гілки: перелік лишається тут, щоб намір був видимий, бо в передпродовому репозиторії
  # нуль викликачів вимірює недобудованість, а не смерть (прецедент [ARCH.103]).
  # Додаючи третій живий рід, додай рядок у `PROTOCOLS` — інакше `ready_for_deployment?`
  # ніколи не спитають, і пристрій мовчатиме без жодної помилки.
  enum :device_type, {
    water_valve: 0,     # Електромагнітний клапан (Посуха / Пожежа) — диспетчеризується
    fire_siren: 1,      # Звукова сирена (Вандалізм / Пожежа) — диспетчеризується
    # ⛔ [ARCH.102] Маяк втратив ЄДИНОГО диспетчера разом із вердиктом `seismic_anomaly`:
    # сейсмічного каналу на дроті не існує, а лічильник `acoustic_events` рахує кавітацію
    # й пилку в одному uint8. Умова повернення — не нова калібровка, а окремий вимірювач.
    seismic_beacon: 2,  # Світлозвуковий маяк — БЕЗ диспетчера
    # ⛔ [ARCH.75] Дока дрона не мала диспетчера ЖОДНОГО дня (перевірено `git log` по
    # `app/services/`), і дротувати її сюди не треба. ⚠️ Обґрунтування ПЕРЕПИСАНО
    # 2026-08-24: доти тут стояло «дешевший дім у bounty-нозі [`E.20`]», а той дім
    # ⚫ won't-do — отже дрон не має дому взагалі, і регуляторна стіна автономного
    # польоту над пожежею нікуди не поділась. Тобто це forward-контракт на ЗАЛІЗО,
    # не заготовка гілки ERS, і тепер — без наступника.
    drone_launcher: 3   # Док-станція дрона — БЕЗ диспетчера
  }, prefix: true

  # [I18N.1] Людська назва РОДУ пристрою — дзеркало `BlockchainTransaction::TOKEN_TYPE_LABEL_SCOPE`.
  # Скоуп належить домену МОДЕЛІ, не компоненту, який показав значення першим (`04_04 §12.14`).
  # ⚠️ Потрібен ширше за UI: `EmergencyResponseService` називає рід пристрою, якого в кластері
  # НЕМА, тобто там немає ані `name`, ані `endpoint` — лишається сам клас [ARCH.75].
  DEVICE_TYPE_LABEL_SCOPE = "actuators.device_types"

  # ОДНА деривація ключа на застосунок: викликач бере цей метод, а не будує
  # `"#{SCOPE}.#{value}"` сам. Класовий, бо рід буває названий БЕЗ запису під рукою.
  # Fail-open: новий член enum'а рендериться сирим значенням, доки мітка не доїде в локалі.
  def self.device_type_label(device_type)
    value = device_type.to_s
    I18n.t("#{DEVICE_TYPE_LABEL_SCOPE}.#{value}", default: value)
  end

  def device_type_label
    self.class.device_type_label(device_type)
  end

  # --- СТАНИ (The Readiness) ---
  enum :state, {
    idle: 0,
    active: 1,
    offline: 2,
    maintenance_needed: 3
  }

  # --- ВАЛІДАЦІЇ ---
  validates :name, :device_type, presence: true
  # endpoint - унікальний шлях CoAP на конкретній Королеві
  validates :endpoint, presence: true, uniqueness: { scope: :gateway_id }

  # Safety Envelope: фізичний ліміт безперервної роботи актуатора (секунди)
  validates :max_active_duration_s, numericality: { greater_than: 0 }, allow_nil: true
  # Energy Budget: орієнтовна витрата енергії за одну активацію (мДж)
  validates :estimated_mj_per_action, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # --- СКОУПИ ---
  scope :operational, -> { where(state: :idle) }

  # =========================================================================
  # ЖИТТЄВИЙ ЦИКЛ ТА СТАТУСИ (AASM State Machine)
  # =========================================================================
  aasm column: :state, enum: true, whiny_persistence: true do
    state :idle, initial: true
    state :active
    state :offline
    state :maintenance_needed

    # Активація пристрою (виклик від ActuatorCommandWorker)
    event :activate do
      before do
        self.last_activated_at = Time.current
      end
      after do
        gateway.touch(:last_seen_at)
        Rails.logger.info "⚙️ [ACTUATOR] #{name} на шлюзі #{gateway.uid} АКТИВОВАНО."
      end
      transitions from: :idle, to: :active
    end

    # Повернення в режим очікування (The Reset)
    event :deactivate do
      after do
        Rails.logger.info "⚙️ [ACTUATOR] #{name} повернувся в стан спокою."
      end
      transitions from: [ :active, :offline, :maintenance_needed ], to: :idle
    end

    # Пристрій втратив зв'язок
    event :go_offline do
      transitions from: [ :idle, :active ], to: :offline
    end

    # Критичний збій (The Hardware Fault)
    event :report_fault do
      after do |reason|
        # Дефолт СВІДОМО прибрано: український літерал тут означав, що
        # «невідома помилка» їде в будь-яку локаль незмінною. Тепер відсутність
        # причини — це ІНШИЙ ключ, а не інший рядок.
        if gateway.cluster_id.present?
          EwsAlert.create!(
            cluster: gateway.cluster,
            alert_type: :system_fault,
            severity: :critical,
            # Дефолт `reason` — теж проза, тож окремий ключ замість українського
            # літерала «Невідома помилка CoAP», що їхав би в будь-яку локаль.
            message_key: reason.present? ? "actuator_fault" : "actuator_fault_unknown",
            message_params: { name: name, endpoint: endpoint, reason: reason }
          )
        end
        Rails.logger.error "🛠️ [ACTUATOR] #{name} ВИЙШОВ З ЛАДУ. Система EWS сповіщена."
      end
      transitions from: [ :idle, :active, :offline ], to: :maintenance_needed
    end
  end

  # [ARCH.75] Safety envelope як ПИТАННЯ, а не лише як валідація: «чи витримає цей
  # пристрій безперервну дію такої тривалості». Дім один, читачів двоє —
  # `ActuatorCommand#duration_within_safety_envelope` (після факту) і
  # `EmergencyResponseService` (ДО запису, бо він пише `insert_all`, тобто повз
  # валідації; рядок, який не проходить власну модель, далі не вміє навіть померти).
  # Порожня стеля = «не оголошено», а не «нуль»: пристрій без заявленого ліміту
  # не обмежуємо — саме тому аварійна відповідь працювала рівно доти, доки колонку
  # лишали порожньою.
  def can_sustain?(seconds)
    max_active_duration_s.blank? || seconds.to_i <= max_active_duration_s
  end

  # Перевірка, чи пристрій готовий до негайного розгортання
  def ready_for_deployment?
    return false unless idle?

    # [СИНХРОНІЗОВАНО]: Шлюз має бути в мережі ТА не перебувати в стані оновлення
    gateway.online? && !gateway.updating?
  end

  # Backward-compatible wrappers для існуючих Workers
  def mark_active!
    activate!
  end

  def mark_idle!
    deactivate!
  end

  # `nil` = причина невідома; фразу для цього випадку добирає локаль
  # (`actuator_fault_unknown`), а не дефолт аргумента.
  def require_maintenance!(reason = nil)
    report_fault!(reason)
  end
end
