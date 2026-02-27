# frozen_string_literal: true

class GatewayTelemetryWorker
  include Sidekiq::Job
  # Використовуємо чергу за замовчуванням (або 'system')
  sidekiq_options queue: "default", retry: 2

  def perform(queen_uid, stats = {})
    # 1. Знаходимо Королеву
    gateway = Gateway.find_by!(uid: queen_uid.to_s.upcase)

    # 2. ТРАНЗАКЦІЙНІСТЬ (System Integrity)
    ActiveRecord::Base.transaction do
      # Створюємо лог стану шлюзу (Battery, Signal, Temp)
      log = gateway.gateway_telemetry_logs.create!(
        voltage_mv: stats["voltage_mv"],
        temperature_c: stats["temperature_c"],
        cellular_signal_csq: stats["cellular_signal_csq"]
      )

      # Відмічаємо активність (last_seen_at)
      gateway.mark_seen!

      # 3. АНАЛІЗ (Self-Preservation)
      check_for_critical_states(gateway, log)
    end

    Rails.logger.info "👑 [Gateway] Шлюз #{gateway.uid} оновлено. V: #{stats['voltage_mv']}mV, CSQ: #{stats['cellular_signal_csq']}"
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "🛑 [Gateway] Спроба оновити невідомий шлюз: #{queen_uid}"
  rescue StandardError => e
    Rails.logger.error "🛑 [Gateway Error] #{e.message}"
    raise e
  end

  private

  def check_for_critical_states(gateway, log)
    # КРИТИЧНО: Напруга < 3300 мВ (Ризик раптового відключення модема)
    if log.voltage_mv < 3300
      alert = EwsAlert.create!(
        tree: nil, # Переконайся, що запустив міграцію нижче!
        cluster: gateway.cluster,
        severity: :critical,
        alert_type: :system_fault,
        message: "КРИТИЧНО: Низький заряд батареї Королеви #{gateway.uid} (#{log.voltage_mv}mV). Ризик втрати зв'язку з сектором!"
      )
      
      # Миттєво викликаємо сповіщення адмінів через наш NotificationWorker
      AlertNotificationWorker.perform_async(alert.id)
    end
  end
end
