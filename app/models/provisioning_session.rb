# frozen_string_literal: true

# [SEC.3] Factory Flashing Pipeline — session state machine.
#
# Represents one Factory-Flashing attempt for one device. Enforces the
# 2-Person Rule documented in docs/03_06 §5 C (operator initiates;
# supervisor approves; only then can the session execute). Every transition
# is auditable through the foreign keys to `users` plus `AuditTrail` writes
# created by `FactoryFlashing::Session`.
#
# `gilka` selects which provisioning branch runs:
#   • "A" → Protected Flash Sector (FLASH_KEY_ADDR + RDP Level 1/2)
#   • "B" → ATECC608B / STSAFE-A110 Secure Element (atecc_serial_hex required)
class ProvisioningSession < ApplicationRecord
  include AASM

  # [SEC.3] Raised when the supervisor's password authentication fails during a
  # 2-Person-Rule approval (see #approve_with_credentials!).
  class SupervisorAuthError < StandardError; end

  GILKAS = %w[A B].freeze
  RDP_LEVELS = [ 0, 1, 2 ].freeze

  belongs_to :operator,   class_name: "User"
  belongs_to :supervisor, class_name: "User", optional: true

  validates :device_uid, :batch_id, :firmware_version, :flash_addr, presence: true
  validates :gilka,      inclusion: { in: GILKAS }
  validates :rdp_level,  inclusion: { in: RDP_LEVELS }
  validates :atecc_serial_hex, presence: true, if: -> { gilka == "B" }
  validates :atecc_serial_hex, format: { with: /\A[0-9A-F]{18}\z/ }, allow_blank: true
  validate  :supervisor_must_differ_from_operator

  aasm column: :state, whiny_persistence: true do
    state :pending, initial: true
    state :supervisor_approved
    state :active
    state :completed
    state :failed

    event :approve do
      transitions from: :pending, to: :supervisor_approved,
                  guard: :supervisor_present?,
                  after: :stamp_supervisor_approval
    end

    event :start do
      transitions from: :supervisor_approved, to: :active,
                  after: -> { update!(started_at: Time.current) }
    end

    event :complete do
      transitions from: :active, to: :completed,
                  after: -> { update!(completed_at: Time.current) }
    end

    event :fail_with do
      transitions from: %i[supervisor_approved active], to: :failed,
                  after: ->(reason) { update!(error_message: reason, completed_at: Time.current) }
    end
  end

  # [SEC.3] Authenticated 2-Person approval: the supervisor must prove possession
  # of their own account (Argon2id password) — an operator who merely *names* a
  # supervisor on the session cannot approve it alone. This is the entry point the
  # factory CLI (`rake factory:approve`) uses. Console/DB access bypasses it
  # (operational boundary — docs/03_06 §5.A access control); the CLI cannot.
  def approve_with_credentials!(supervisor_password)
    raise SupervisorAuthError, "session has no supervisor assigned" if supervisor.blank?

    unless supervisor.authenticate(supervisor_password)
      raise SupervisorAuthError, "supervisor password authentication failed"
    end

    approve!
  end

  private

  def supervisor_present?
    supervisor_id.present? && supervisor_id != operator_id
  end

  def stamp_supervisor_approval
    update!(supervisor_approved_at: Time.current)
  end

  def supervisor_must_differ_from_operator
    return if supervisor_id.blank?

    errors.add(:supervisor_id, "must differ from operator (2-Person Rule)") if supervisor_id == operator_id
  end
end
