# frozen_string_literal: true

class ActuatorCommand < ApplicationRecord
  belongs_to :actuator
  belongs_to :ews_alert, optional: true
  belongs_to :user, optional: true

  enum :status, {
    issued: 0,
    sent: 1,
    acknowledged: 2,
    failed: 3,
    confirmed: 4
  }, prefix: true

  validates :command_payload, presence: true
  validates :duration_seconds, presence: true,
                               numericality: { greater_than: 0, less_than_or_equal_to: 3600 }

  after_commit :dispatch_to_edge!, on: :create

  scope :recent, -> { order(created_at: :desc).limit(10) }
  scope :pending, -> { where(status: [ :issued, :sent ]) }

  def estimated_completion_at
    return nil unless sent_at
    sent_at + duration_seconds.seconds
  end

  private

  def dispatch_to_edge!
    # Транслюємо створення в UI
    broadcast_prepend_to_activity_feed

    if actuator.ready_for_deployment?
      ActuatorCommandWorker.perform_async(self.id)
    else
      update_columns(status: self.class.statuses[:failed], error_message: "Актуатор недоступний")
      Rails.logger.warn "🛑 [COMMAND] Спроба активації ##{id} провалена: Актуатор #{actuator.name} недоступний."
    end
  end

  def broadcast_prepend_to_activity_feed
    org = actuator.gateway&.cluster&.organization
    return unless org

    Turbo::StreamsChannel.broadcast_prepend_to(
      org,
      target: "recent_commands_feed",
      html: Views::Components::Actuators::CommandRow.new(command: self).call
    )
  end
end
