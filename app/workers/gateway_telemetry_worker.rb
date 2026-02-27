# frozen_string_literal: true

class GatewayTelemetryWorker
  include Sidekiq::Job
  # Використовуємо чергу для системних логів (нижчий пріоритет, ніж телеметрія дерев)
  sidekiq_options queue: "default", retry: 2

  def perform(queen_uid, stats = {})
    # 1. Знаходимо Королеву
    gateway = Gateway.find_by!(uid: queen_uid.to_s.upcase)

    # 2. ТРАНЗАКЦІЙНІСТЬ ТА ОНОВЛЕННЯ
    ActiveRecord::Base.transaction do
      # Створюємо лог стану шлюзу
      log = gateway.gateway_telemetry_logs.create!(
        voltage_mv: stats["voltage_mv"],
        temperature_c: stats["temperature_c"],
        cellular_signal_csq: stats["cellular_signal_csq"]
      )

      # Відмічаємо, що шлюз "живий" і на зв'язку
      gateway.mark_seen!

      # 3. ЕКСТРЕНИЙ АНАЛІЗ (Self-Preservation)
      check_for_critical_states(gateway, log)
    end

    Rails.logger.info "👑 [Gateway] Стан Королеви #{queen_uid} оновлено: #{stats['voltage_mv']}mV, CSQ: #{stats['cellular_signal_csq']}"
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "🛑 [Gateway] Спроба оновити невідомий шлюз: #{queen_uid}"
  rescue StandardError => e
    Rails.logger.error "🛑 [Gateway Error] #{e.message}"
    raise e
  end

  private

  def check_for_critical_states(gateway, log)
    # Якщо напруга критична (напр. < 3300 мВ), створюємо системний алерт
    if log.voltage_mv < 3300
      EwsAlert.create!(
        tree: nil, # Алерт стосується шлюзу, а не конкретного дерева
        cluster: gateway.cluster,
        severity: :critical,
        alert_type: :system_fault,
        description: "КРИТИЧНО: Низький заряд батареї Королеви #{gateway.uid} (#{log.voltage_mv}mV). Ризик відключення сектору!"
      )
      
      # Можна також викликати негайне сповіщення адміна
      # AlertNotificationWorker.perform_async(...)
    end
  end
end
