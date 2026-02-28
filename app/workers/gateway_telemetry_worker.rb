# frozen_string_literal: true

class GatewayTelemetryWorker
  include Sidekiq::Job
  sidekiq_options queue: "default", retry: 2

  def perform(queen_uid, stats = {})
    # 1. Знаходимо Королеву (Синхронізація регістру DID/UID)
    gateway = Gateway.find_by!(uid: queen_uid.to_s.strip.upcase)

    # 2. ТРАНЗАКЦІЙНІСТЬ (System Integrity)
    ActiveRecord::Base.transaction do
      # Створюємо лог стану (Використовуємо символи для доступу до Hash, якщо це Sidekiq JSON)
      stats = stats.with_indifferent_access
      
      log = gateway.gateway_telemetry_logs.create!(
        voltage_mv: stats[:voltage_mv],
        temperature_c: stats[:temperature_c],
        cellular_signal_csq: stats[:cellular_signal_csq]
      )

      # Оновлюємо пульс та IP-адресу (якщо прийшла в stats)
      gateway.mark_seen!(stats[:ip_address])

      # 3. АНАЛІЗ (Self-Preservation)
      # Використовуємо логіку, яку ми зашліфували в моделі лога
      check_system_health(gateway, log)
    end

    Rails.logger.info "👑 [Gateway] Шлюз #{gateway.uid} оновлено. V: #{stats[:voltage_mv]}mV, CSQ: #{stats[:cellular_signal_csq]}"
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "🛑 [Gateway] Спроба оновити невідомий шлюз: #{queen_uid}"
  rescue StandardError => e
    Rails.logger.error "🛑 [Gateway Error] #{gateway&.uid}: #{e.message}"
    raise e
  end

  private

  def check_system_health(gateway, log)
    # Якщо модель зафіксувала критичний стан (батарея або температура)
    return unless log.critical_fault?

    message = if log.voltage_mv < 3300
                "КРИТИЧНО: Низький заряд батареї Королеви #{gateway.uid} (#{log.voltage_mv}mV). Ризик вимкнення!"
              elsif log.temperature_c > 65
                "УВАГА: Перегрів Королеви #{gateway.uid} (#{log.temperature_c}°C). Системна деградація!"
              else
                "Аномальний стан заліза Королеви #{gateway.uid}."
              end

    # Створюємо тривогу (EwsAlert)
    alert = EwsAlert.create!(
      cluster: gateway.cluster,
      severity: :critical,
      alert_type: :system_fault,
      message: message
    )
    
    # Запускаємо сповіщення Патрульних (The Patrolman's Voice)
    AlertNotificationWorker.perform_async(alert.id)
  end
end
