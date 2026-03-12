# frozen_string_literal: true

class ActuatorCommand < ApplicationRecord
  include AASM

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

    # Підтвердження отримання від шлюзу (ACK)
    event :acknowledge do
      before do
        self.sent_at ||= Time.current
      end
      transitions from: :sent, to: :acknowledged
    end

    # Підтвердження виконання команди актуатором
    event :confirm do
      before do
        self.completed_at = Time.current
      end
      transitions from: :acknowledged, to: :confirmed
    end

    # Збій на будь-якому етапі
    event :fail do
      before do |reason|
        self.error_message = reason.to_s.truncate(200) if reason.present?
      end
      transitions from: [ :issued, :sent, :acknowledged, :confirmed, :failed ], to: :failed
    end
  end

  # 🛑 Команди, що мають системний пріоритет OVERRIDE.
  # При створенні такої команди всі pending-команди для цього актуатора скасовуються.
  OVERRIDE_COMMANDS = %w[STOP EMERGENCY_SHUTDOWN EMERGENCY_STOP].freeze

  ALLOWED_PAYLOAD_FORMAT = /\A[A-Z_]+(?::\d+)?\z/

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
                               numericality: { greater_than: 0, less_than_or_equal_to: 3600 }
  validates :idempotency_token, presence: true, uniqueness: true
  validates :priority, presence: true
  validate :duration_within_safety_envelope
  validate :expires_at_in_future, on: :create

  after_commit :dispatch_to_edge!, on: :create
  # 🛑 Override: скасовуємо всі pending-команди для актуатора при STOP/EMERGENCY_SHUTDOWN
  after_commit :cancel_pending_for_actuator!, on: :create, if: :priority_override?

  scope :recent, -> { order(created_at: :desc).limit(10) }
  scope :pending, -> { where(status: [ :issued, :sent ]) }
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

  # 🛡️ Генеруємо унікальний токен для кожної команди
  def assign_idempotency_token
    self.idempotency_token ||= SecureRandom.uuid
  end

  # 📈 Денормалізація: зберігаємо organization_id прямо в команді
  def denormalize_organization
    self.organization_id ||= actuator&.gateway&.cluster&.organization_id
  end

  # Safety Envelope: тривалість команди не може перевищувати фізичний ліміт актуатора
  def duration_within_safety_envelope
    return unless actuator&.max_active_duration_s.present? && duration_seconds.present?

    if duration_seconds > actuator.max_active_duration_s
      errors.add(:duration_seconds, "перевищує безпечний ліміт актуатора (#{actuator.max_active_duration_s}с)")
    end
  end

  # ⏱️ TTL: expires_at має бути в майбутньому при створенні
  def expires_at_in_future
    return unless expires_at.present?

    if expires_at <= Time.current
      errors.add(:expires_at, "має бути в майбутньому")
    end
  end

  # 🛑 Auto-override: команди STOP/EMERGENCY_SHUTDOWN завжди отримують override-пріоритет
  def enforce_override_priority
    base_command = command_payload.to_s.split(":").first
    self.priority = :override if OVERRIDE_COMMANDS.include?(base_command)
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
    end
  end

  def dispatch_to_edge!
    # ⏱️ TTL: перевіряємо актуальність перед диспетчеризацією
    if expired?
      update_columns(status: self.class.statuses[:failed], error_message: "Команда протермінована (TTL)")
      Rails.logger.warn "⏱️ [COMMAND] Команда ##{id} протермінована до відправки."
      return
    end

    # Транслюємо створення в UI
    broadcast_prepend_to_activity_feed

    if actuator.ready_for_deployment?
      ActuatorCommandWorker.perform_async(self.id)
    else
      update_columns(status: self.class.statuses[:failed], error_message: "Актуатор недоступний")
      Rails.logger.warn "🛑 [COMMAND] Спроба активації ##{id} провалена: Актуатор #{actuator.name} недоступний."
    end
  end

  # 📈 Використовуємо денормалізований organization_id замість глибокого JOIN
  def broadcast_prepend_to_activity_feed
    org = organization || actuator.gateway&.cluster&.organization
    return unless org

    Turbo::StreamsChannel.broadcast_prepend_to(
      org,
      target: "recent_commands_feed",
      html: Actuators::CommandRow.new(command: self).call
    )
  end
end
