# frozen_string_literal: true

class EcosystemHealingWorker
  include Sidekiq::Job
  # Відновлення екосистеми після EWS-тривог є критичною операцією:
  # реанімація актуаторів, зняття з експлуатації, закриття тривог.
  sidekiq_options queue: "critical", retry: 3

  def perform(record_id)
    record = MaintenanceRecord.find(record_id)
    target = record.maintainable

    # [P0 FIX]: Sidekiq job НЕ повинен ставитись в чергу всередині транзакції.
    # Збираємо record_id для PuroEarthPassportWorker під час транзакції, enqueue — після commit.
    pending_passport_record_id = nil

    ActiveRecord::Base.transaction do
      # 1. ОСВІЖЕННЯ ПУЛЬСУ
      target.mark_seen! if target.respond_to?(:mark_seen!)

      # 2. РЕАНІМАЦІЯ АКТУАТОРІВ
      # [SAFETY]: guard may_deactivate? — repair-запис на вже-idle актуаторі
      # (preventive maintenance) інакше кидав AASM::InvalidTransition (mark_idle! =
      # deactivate!, валідний лише from active/offline/maintenance_needed) →
      # транзакція відкочувалась → alert.resolve! (крок 4) недосяжний → retry→dead.
      if target.is_a?(Actuator) && record.action_type_repair? && target.may_deactivate?
        target.mark_idle!
      end

      # 3. ЖИТТЄВИЙ ЦИКЛ ДЕРЕВА
      if target.is_a?(Tree) && record.action_type_decommissioning? && target.may_decommission?
        target.decommission!
      end

      # 3a. AFTERLIFE ECONOMY (Puro.earth Biochar D-MRV)
      # Biomass extraction marks a dead tree and initiates Biomass Passport generation
      # for Puro.earth CORC certification. The passport anchors provenance on-chain.
      if target.is_a?(Tree) && record.action_type_biomass_extraction?
        target.declare_deceased! unless target.deceased?
        pending_passport_record_id = record.id
      end

      # 4. [ВИПРАВЛЕНО]: ЗАКРИТТЯ ТРИВОГИ (Enum Method Fix)
      # Тепер використовуємо status_resolved? замість resolved?
      alert = record.ews_alert
      if alert.present? && !alert.status_resolved?
        resolution_msg = "🔧 Відновлено: #{record.action_type.humanize}. Запис ##{record.id}."
        alert.resolve!(user: record.user, notes: resolution_msg)
      end
    end

    # Enqueue passport worker ПІСЛЯ успішного commit транзакції
    PuroEarthPassportWorker.perform_async(pending_passport_record_id) if pending_passport_record_id
  end
end
