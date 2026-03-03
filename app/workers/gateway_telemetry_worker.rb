# frozen_string_literal: true

class GatewayTelemetryWorker
  include Sidekiq::Job
  # Шлюзи оновлюються рідше за дерева, тому використовуємо чергу за замовчуванням
  sidekiq_options queue: "default", retry: 2

  def perform(queen_uid, stats = {})
    # Підготовлюємо хеш один раз на початку, уникаючи зайвих алокацій в транзакції
    stats = stats.with_indifferent_access

    # 1. Знаходимо Королеву
    gateway = Gateway.find_by!(uid: queen_uid.to_s.strip.upcase)

    # 2. ТРАНЗАКЦІЙНІСТЬ (The Integrity Loop)
    ActiveRecord::Base.transaction do
      log = gateway.gateway_telemetry_logs.create!(
        voltage_mv: stats[:voltage_mv],
        temperature_c: stats[:temperature_c],
        cellular_signal_csq: stats[:cellular_signal_csq]
      )

      # [СИНХРОНІЗОВАНО з Gateway v2.2]:
      # Тепер ми передаємо voltage_mv безпосередньо в mark_seen!
      # Це забезпечує денормалізацію даних та прибирає N+1 при перевірці батареї.
      gateway.mark_seen!(
        new_ip: stats[:ip_address],
        voltage_mv: stats[:voltage_mv]
      )

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
    # Використовуємо метод моделі для визначення деградації заліза
    return unless log.respond_to?(:critical_fault?) && log.critical_fault?

    # Формуємо вердикт для патрульного
    message = format_health_message(gateway, log)

    # Створюємо тривогу (EwsAlert)
    return unless gateway.cluster_id

    alert = EwsAlert.create!(
      cluster_id: gateway.cluster_id,
      severity: :critical,
      alert_type: :system_fault,
      message: message
    )

    # Викликаємо "Голос Патрульних" (SMS/Telegram)
    AlertNotificationWorker.perform_async(alert.id)
  end

  def format_health_message(gateway, log)
    if log.voltage_mv < GatewayTelemetryLog::LOW_BATTERY_THRESHOLD
      "🔋 КРИТИЧНО: Королева #{gateway.uid} виснажена (#{log.voltage_mv}mV). Скоро відключення!"
    elsif log.temperature_c > GatewayTelemetryLog::OVERHEAT_THRESHOLD
      "🔥 УВАГА: Королева #{gateway.uid} перегріта (#{log.temperature_c}°C). Можлива деформація корпусу."
    elsif log.cellular_signal_csq.to_i < GatewayTelemetryLog::LOW_SIGNAL_THRESHOLD
      "📡 ЗВ'ЯЗОК: Слабкий сигнал на #{gateway.uid} (CSQ: #{log.cellular_signal_csq}). Ризик втрати батчів."
    else
      "🛠️ Апаратний збій Королеви #{gateway.uid}. Потрібен огляд."
    end
  end
end
