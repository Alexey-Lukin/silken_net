# SPDX-License-Identifier: AGPL-3.0-or-later
# frozen_string_literal: true

class ActuatorCommand < ApplicationRecord
  include AASM
  include Auditable

  belongs_to :actuator
  belongs_to :ews_alert, optional: true
  belongs_to :user, optional: true
  # 📈 Денормалізація: усуваємо N+1 JOIN actuator->gateway->cluster->organization
  belongs_to :organization, optional: true

  enum :status, {
    issued: 0,
    sent: 1,
    acknowledged: 2,
    failed: 3,
    confirmed: 4
  }, prefix: true

  # [UI.3] Стани, після яких команда вже не рухається. Дім ОДИН: SR-анонс на
  # `Actuators::Show` озвучує рівно їх (присуд 2026-08-20 — проміжні мовчать,
  # інакше батч на 20 рядків дає шквал), і його спека деривує перелік звідси.
  TERMINAL_STATUSES = %w[confirmed failed].freeze

  # 🚦 Ієрархія Виживання: сирена має витіснити полив
  enum :priority, {
    low: 0,      # плановий полив
    medium: 1,   # діагностика
    high: 2,     # критичне реагування EWS
    override: 3  # STOP / EMERGENCY_SHUTDOWN — обнуляє всі pending для актуатора
  }, prefix: true

  # =========================================================================
  # ЖИТТЄВИЙ ЦИКЛ КОМАНДИ (AASM State Machine)
  # =========================================================================
  # [ARCH.57] Актуатор = фізична дія в лісі (сирена/клапан) — кожна зміна статусу
  # у audit-ланцюг; chain-only (не IPFS), ініціатор-людина зберігається як актор.
  # after_update_commit, НЕ AASM after_all_transitions: той файрить ДО персистенції —
  # rollback переходу лишав би фантомний рядок (Sidekiq-push не відкочується);
  # saved_change-guard заразом глушить self-loop failed→failed (no-op write).
  after_update_commit :record_actuator_audit_trail, if: :saved_change_to_status?

  aasm column: :status, enum: true, whiny_persistence: true do
    state :issued, initial: true
    state :sent
    state :acknowledged
    state :failed
    state :confirmed

    # Відправка команди на edge-пристрій через CoAP
    event :dispatch do
      before do
        self.sent_at = Time.current
      end
      transitions from: :issued, to: :sent
    end

    # Підтвердження отримання від шлюзу (ACK).
    # ACK означає, що edge-actuator прийняв команду до виконання — це той
    # момент, коли фізично починається дія (відкриття клапана, активація
    # сирени). UI Actuators::Show рендерить саме цю мітку у колонці
    # "executed_at"; без присвоєння тут вона мовчки лишалась би nil
    # (silent dead column — раніше встановлювалось лише через seeds.rb).
    event :acknowledge do
      before do
        self.sent_at ||= Time.current
        self.executed_at ||= Time.current
      end
      transitions from: :sent, to: :acknowledged
    end

    # Підтвердження виконання команди актуатором
    event :confirm do
      before do
        self.executed_at ||= Time.current
        self.completed_at = Time.current
      end
      transitions from: :acknowledged, to: :confirmed
    end

    # Збій на будь-якому етапі
    event :fail do
      before do |reason|
        self.error_message = reason.to_s.truncate(200) if reason.present?
      end
      # :failed → :failed дозволяє оновити error_message при повторному збої
      # (напр. sidekiq_retries_exhausted після ручного fail з handle_failure)
      transitions from: [ :issued, :sent, :acknowledged, :confirmed, :failed ], to: :failed
    end
  end

  # 🛑 Команди, що мають системний пріоритет OVERRIDE.
  # При створенні такої команди всі pending-команди для цього актуатора скасовуються.
  OVERRIDE_COMMANDS = %w[STOP EMERGENCY_SHUTDOWN EMERGENCY_STOP].freeze

  ALLOWED_PAYLOAD_FORMAT = /\A[A-Z_]+(?::\d+)?\z/

  # [ARCH.75] Протокольна стеля ОДНІЄЇ команди — дім один. Доти те саме число
  # стояло двома незв'язаними літералами: тут у валідації й `MAX_COMMAND_DURATION`
  # в `EmergencyResponseService`, який ріже чанки. Розійтись вони могли мовчки —
  # жоден гейт їх не звіряв, — а наслідок розходження недешевий: сервіс нарізав би
  # чанки, які модель не приймає, і `insert_all` поклав би їх у БД повз валідації.
  # ⚠️ Це стеля ПРОТОКОЛУ (скільки вміє нести один наказ), а НЕ фізична стеля
  # пристрою — та живе на `Actuator#max_active_duration_s` і питається через
  # `Actuator#can_sustain?`. Дві різні величини, і плутати їх коштувало ARCH.75.
  MAX_DURATION_S = 3600

  # [ARCH.58] Один дім деривації «це override?»: `enforce_override_priority`
  # ставить пріоритет ПІСЛЯ валідації, а контролеру треба знати відповідь ДО
  # створення запису (in-flight гард). Без спільного методу правило жило б у
  # двох місцях і розійшлось би на першій же зміні `OVERRIDE_COMMANDS`.
  def self.override_payload?(payload)
    OVERRIDE_COMMANDS.include?(payload.to_s.split(":").first)
  end

  # 🛡️ Idempotency: UUID генерується автоматично перед валідацією
  before_validation :assign_idempotency_token, on: :create
  # 📈 Денормалізація: organization_id заповнюється з ланцюжка actuator->gateway->cluster
  before_validation :denormalize_organization, on: :create
  # 🛑 Auto-override: STOP/EMERGENCY_SHUTDOWN автоматично отримують override-пріоритет
  before_validation :enforce_override_priority, on: :create

  validates :command_payload, presence: true,
                              format: { with: ALLOWED_PAYLOAD_FORMAT,
                                        message: "дозволені лише команди формату ACTION або ACTION:value (напр. OPEN:60)" }
  validates :duration_seconds, presence: true,
                               numericality: { greater_than: 0, less_than_or_equal_to: MAX_DURATION_S }
  validates :idempotency_token, presence: true, uniqueness: true
  validates :priority, presence: true
  validate :duration_within_safety_envelope
  validate :expires_at_in_future, on: :create

  after_commit :dispatch_to_edge!, on: :create
  # 🛑 Override: скасовуємо всі pending-команди для актуатора при STOP/EMERGENCY_SHUTDOWN
  after_commit :cancel_pending_for_actuator!, on: :create, if: :priority_override?

  scope :recent, -> { order(created_at: :desc).limit(10) }
  scope :pending, -> { where(status: [ :issued, :sent ]) }
  # [ARCH.58] «Живий» = ще може бути виданий. Протермінований наказ матеріалізує
  # свій кінець ЛИШЕ в момент poll-видачі (`Downlink::PendingQueueService`), тож
  # на мертвому шлюзі труп лежить у `.pending` вічно — і без цього скоупа він
  # тримав би 409 для всіх нових наказів назавжди, а sweep'у глушив би ногу STOP.
  # Один дім для TTL-половини означення. ⚠️ Тотожності викликачів це не дає:
  # sweep звужує скоуп ще й вік-межею (наказ БЕЗ `expires_at` не протермінується
  # ніколи), тож «живий» там суворіший — і це свідомо, не дрейф.
  scope :live_pending, -> { pending.where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :expired, -> { pending.where("expires_at IS NOT NULL AND expires_at < ?", Time.current) }
  scope :by_priority, -> { order(priority: :desc, created_at: :asc) }

  def estimated_completion_at
    return nil unless sent_at
    sent_at + duration_seconds.seconds
  end

  # ⏱️ TTL: перевіряємо, чи команда ще актуальна
  def expired?
    expires_at.present? && expires_at < Time.current
  end

  private

  # [ARCH.57] update_columns у dispatch_to_edge! свідомо обходить валідації (і колбеки) —
  # ланцюг закривається ручним викликом; ім'я те саме state-based, що дав би хук.
  def record_pre_dispatch_failure_audit!(reason)
    record_audit_trail!(
      action: "actuator_to_failed",
      organization_id: organization_id,
      user_id: user_id,
      metadata: { actuator_id: actuator_id, ews_alert_id: ews_alert_id,
                  priority: priority.to_s, from: "issued", to: "failed", reason: reason }
    )
  end

  # [ARCH.57] user_id = людський ініціатор, якщо є (EWS-автоматика → oracle_executioner).
  # Імена state-based: update_columns/raw-шляхи не мають AASM-події.
  def record_actuator_audit_trail
    from, to = saved_change_to_status
    record_audit_trail!(
      action: "actuator_to_#{to}",
      organization_id: organization_id,
      user_id: user_id,
      metadata: {
        actuator_id: actuator_id, ews_alert_id: ews_alert_id, priority: priority.to_s,
        from: from.to_s, to: to.to_s
      }
    )
  end

  # 🛡️ Генеруємо унікальний токен для кожної команди
  def assign_idempotency_token
    self.idempotency_token ||= SecureRandom.uuid
  end

  # 📈 Денормалізація: зберігаємо organization_id прямо в команді
  def denormalize_organization
    self.organization_id ||= actuator&.gateway&.cluster&.organization_id
  end

  # Safety Envelope: тривалість команди не може перевищувати фізичний ліміт актуатора.
  # Саме питання живе на пристрої (`Actuator#can_sustain?`) — тут лише його наслідок
  # для запису, бо ТОЙ САМИЙ предикат мусить бути доступний ДО створення рядка:
  # `EmergencyResponseService` пише `insert_all` повз валідації [ARCH.75].
  def duration_within_safety_envelope
    return if actuator.nil? || duration_seconds.blank?
    return if actuator.can_sustain?(duration_seconds)

    errors.add(:duration_seconds, :exceeds_actuator_limit, limit: actuator.max_active_duration_s)
  end

  # ⏱️ TTL: expires_at має бути в майбутньому при створенні
  def expires_at_in_future
    return unless expires_at.present?

    if expires_at <= Time.current
      errors.add(:expires_at, :must_be_future)
    end
  end

  # 🛑 Auto-override: команди STOP/EMERGENCY_SHUTDOWN завжди отримують override-пріоритет
  def enforce_override_priority
    self.priority = :override if self.class.override_payload?(command_payload)
  end

  # 🛑 Override: скасовуємо ВСІ pending-команди для цього актуатора (крім поточної).
  # Це гарантує, що STOP не чекатиме в черзі за OPEN.
  def cancel_pending_for_actuator!
    cancelled_count = actuator.commands
      .pending
      .where.not(id: id)
      .update_all(
        status: self.class.statuses[:failed],
        error_message: "Скасовано override-командою ##{id} (#{command_payload})"
      )

    if cancelled_count > 0
      Rails.logger.warn "🛑 [OVERRIDE] Команда ##{id} (#{command_payload}) скасувала #{cancelled_count} pending-команд для актуатора #{actuator_id}."
      # [ARCH.57] update_all обходить колбеки → один сукупний audit-рядок за bulk-скасування
      # (physical-safety trail: emergency-override не сміє бути невидимим у ланцюзі).
      record_audit_trail!(
        action: "actuator_bulk_cancelled",
        organization_id: organization_id,
        user_id: user_id,
        metadata: { actuator_id: actuator_id, cancelled_count: cancelled_count,
                    override_command_id: id, command_payload: command_payload }
      )
    end
  end

  def dispatch_to_edge!
    # ⏱️ TTL: перевіряємо актуальність перед диспетчеризацією
    if expired?
      update_columns(status: self.class.statuses[:failed], error_message: "Команда протермінована (TTL)")
      record_pre_dispatch_failure_audit!("ttl_expired")
      Rails.logger.warn "⏱️ [COMMAND] Команда ##{id} протермінована до відправки."
      return
    end

    # [ARCH.58] Override (STOP/EMERGENCY_*) СВІДОМО минає readiness-гейт.
    # `ready_for_deployment?` вимагає `idle?`, тож аварійна зупинка гинула саме
    # на ПРАЦЮЮЧОМУ актуаторі — рівно в тому стані, заради якого override існує.
    # Виміряно: команда лишалась `failed` «Актуатор недоступний», а
    # `cancel_pending_for_actuator!` (той самий after_commit) встигав знести
    # решту черги — нетто гірше за бездіяльність. Ширше: гейт — артефакт
    # push-ери, коли «зайнято» справді означало «не доставимо»; під
    # poll-семантикою [FW.60] команда просто чекає в `.pending`, а чесний
    # строк життя дає `expires_at`.
    return if priority_override?

    unless actuator.ready_for_deployment?
      update_columns(status: self.class.statuses[:failed], error_message: "Актуатор недоступний")
      record_pre_dispatch_failure_audit!("actuator_not_ready")
      Rails.logger.warn "🛑 [COMMAND] Спроба активації ##{id} провалена: Актуатор #{actuator.name} недоступний."
    end
    # [FW.60] Push-enqueue (ActuatorCommandWorker) superseded: команда чекає
    # в .pending — Королева забере її власним poll'ом після наступного флашу
    # (Downlink::PendingQueueService, пріоритет CMD найвищий). Push у
    # CGNAT-egress не лише не долітав — його швидкі ретраї fail!'или команду
    # ДО того, як Queen могла її запитати.
  end
end
