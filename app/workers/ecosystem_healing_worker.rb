# frozen_string_literal: true

class EcosystemHealingWorker
  include Sidekiq::Job
  # Відновлення екосистеми після EWS-тривог є критичною операцією:
  # реанімація актуаторів, зняття з експлуатації, закриття тривог.
  sidekiq_options queue: "critical", retry: 3

  def perform(record_id)
    record = MaintenanceRecord.find(record_id)
    target = record.maintainable

    ActiveRecord::Base.transaction do
      # 1. ОСВІЖЕННЯ ПУЛЬСУ
      target.mark_seen! if target.respond_to?(:mark_seen!)

      # 2. РЕАНІМАЦІЯ АКТУАТОРІВ
      if target.is_a?(Actuator) && record.action_type_repair?
        target.mark_idle!
      end

      # 3. ЖИТТЄВИЙ ЦИКЛ ДЕРЕВА
      if target.is_a?(Tree) && record.action_type_decommissioning?
        target.update!(status: :removed)
      end

      # 4. [ВИПРАВЛЕНО]: ЗАКРИТТЯ ТРИВОГИ (Enum Method Fix)
      # Тепер використовуємо status_resolved? замість resolved?
      alert = record.ews_alert
      if alert.present? && !alert.status_resolved?
        resolution_msg = "🔧 Відновлено: #{record.action_type.humanize}. Запис ##{record.id}."
        alert.resolve!(user: record.user, notes: resolution_msg)
      end
    end
  end
end
