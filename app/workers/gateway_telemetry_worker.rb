# frozen_string_literal: true

class GatewayTelemetryWorker
  include Sidekiq::Job
  # Шлюзи оновлюються рідше за дерева, тому використовуємо чергу за замовчуванням
  sidekiq_options queue: "default", retry: 2

  def perform(queen_uid, stats = {})
    # 1. Знаходимо Королеву
    gateway = Gateway.find_by!(uid: queen_uid.to_s.strip.upcase)

    # 2. ТРАНЗАКЦІЙНІСТЬ (The Integrity Loop)
    ActiveRecord::Base.transaction do
      stats = stats.with_indifferent_access

      log = gateway.gateway_telemetry_logs.create!(
        voltage_mv: stats[:voltage_mv],
        temperature_c: stats[:temperature_c],
        cellular_signal_csq: stats[:cellular_signal_csq]
      )

      # Оновлюємо пульс та IP-адресу Starlink/LTE модема
      gateway.mark_seen!(stats[:ip_address])

      # 3. АНАЛІЗ (The Diagnostic Lens)
      check_system_health(gateway, log)
    end

    Rails.logger.info "👑 [Gateway] #{gateway.uid} Sync: #{stats[:voltage_mv]}mV, Sig: #{stats[:cellular_signal_csq]}/31"
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "🛑 [Gateway] Спроба оновити фантомний шлюз: #{queen_uid}"
  rescue StandardError => e
    Rails.logger.error "🛑 [Gateway Error] Збій у матриці #{gateway&.uid}: #{e.message}"
    raise e
  end

  private

  def check_system_health(gateway, log)
    # [СИНХРОНІЗОВАНО]: Використовуємо метод моделі для визначення деградації заліза
    return unless log.respond_to?(:critical_fault?) && log.critical_fault?

    # Формуємо вердикт для патрульного
    message = format_health_message(gateway, log)

    # Створюємо тривогу (EwsAlert)
    # Переконуємося, що шлюз прив'язаний до кластера, інакше тривога піде "в нікуди"
    return unless gateway.cluster_id

    alert = EwsAlert.create!(
      cluster_id: gateway.cluster_id,
      severity: :critical,
      alert_type: :system_fault, # [СИНХРОНІЗОВАНО] з нашою моделлю EwsAlert
      message: message
    )

    # Викликаємо "Голос Патрульних" (SMS/Telegram)
    AlertNotificationWorker.perform_async(alert.id)
  end

  def format_health_message(gateway, log)
    if log.voltage_mv < 3300
      "🔋 КРИТИЧНО: Королева #{gateway.uid} виснажена (#{log.voltage_mv}mV). Скоро відключення!"
    elsif log.temperature_c > 65
      "🔥 УВАГА: Королева #{gateway.uid} перегріта (#{log.temperature_c}°C). Можлива деформація корпусу."
    elsif log.cellular_signal_csq.to_i < 5
      "📡 ЗВ'ЯЗОК: Слабкий сигнал на #{gateway.uid} (CSQ: #{log.cellular_signal_csq}). Ризик втрати батчів."
    else
      "🛠️ Апаратний збій Королеви #{gateway.uid}. Потрібен огляд."
    end
  end
end
