# frozen_string_literal: true

# [SEC.3] Factory Flashing Pipeline — session state machine.
#
# Represents one Factory-Flashing attempt for one device. Enforces the
# 2-Person Rule documented in docs/03_06 §5.C (operator initiates;
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
      # [SEC.3] Two guards: the 2-Person Rule (supervisor present & differs from the
      # operator) AND proof that the supervisor's password was verified *this call*
      # via #approve_with_credentials!. A bare `approve!` (e.g. from a Rails console)
      # leaves @credentials_verified false → the transition is refused. This closes
      # the console self-approve path in code; raw-SQL / object manipulation remains
      # an operational boundary (docs/03_06 §5.A access control).
      transitions from: :pending, to: :supervisor_approved,
                  guard: %i[supervisor_present? credentials_verified?],
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
  # factory CLI (`rake factory:approve`) uses, and the ONLY path that sets
  # @credentials_verified, so the AASM `approve` guard accepts the transition.
  # Console/DB access bypasses it (operational boundary — docs/03_06 §5.A access
  # control); the CLI and a bare `approve!` cannot.
  def approve_with_credentials!(supervisor_password)
    raise SupervisorAuthError, "session has no supervisor assigned" if supervisor.blank?

    unless supervisor.authenticate(supervisor_password)
      raise SupervisorAuthError, "supervisor password authentication failed"
    end

    # [SEC.3] Flag the verification so the AASM `approve` guard accepts this call,
    # then reset in `ensure` so it can never linger past this single transition.
    @credentials_verified = true
    approve!
  ensure
    @credentials_verified = false
  end

  private

  def supervisor_present?
    supervisor_id.present? && supervisor_id != operator_id
  end

  # [SEC.3] True only inside #approve_with_credentials!, after the supervisor's
  # password authenticates — the AASM `approve` guard requires it, so a raw
  # `approve!` (no credential check) cannot reach :supervisor_approved.
  def credentials_verified?
    @credentials_verified == true
  end

  def stamp_supervisor_approval
    update!(supervisor_approved_at: Time.current)
  end

  def supervisor_must_differ_from_operator
    return if supervisor_id.blank?

    errors.add(:supervisor_id, "must differ from operator (2-Person Rule)") if supervisor_id == operator_id
  end
end
