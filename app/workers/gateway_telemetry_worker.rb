# frozen_string_literal: true

class GatewayTelemetryWorker
  include Sidekiq::Job
  # Телеметрія шлюзів — це вхідний потік даних, аналогічний UnpackTelemetryWorker.
  # Черга uplink гарантує, що діагностика Королев (батарея, температура, сигнал)
  # не затримується за рутинними задачами в default.
  sidekiq_options queue: "uplink", retry: 2

  # CSQ 0-31 — нормальний діапазон (3GPP 27.007); 99 — невизначений/відсутній сигнал
  VALID_CSQ_VALUES = (0..31).freeze

  def perform(queen_uid, stats = {})
    # Підготовлюємо хеш один раз на початку, уникаючи зайвих алокацій в транзакції
    stats = stats.with_indifferent_access

    # 1. Знаходимо Королеву
    gateway = Gateway.find_by!(uid: queen_uid.to_s.strip.upcase)

    # [KENOSIS TITAN]: Перевірка якості даних на рівні обробника.
    # Замінює AR-валідації, які ігноруються при insert_all на Series D масштабі.
    unless valid_gateway_stats?(stats)
      Rails.logger.warn "⚠️ [Gateway] Пакет від #{gateway.uid} відхилено: невалідні дані сенсорів."
      return
    end

    # 2. ТРАНЗАКЦІЙНІСТЬ (The Integrity Loop)
    ActiveRecord::Base.transaction do
      log = gateway.gateway_telemetry_logs.create!(
        gateway_id: gateway.id,
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

  # [KENOSIS TITAN]: Перевірка якості даних сенсорів на рівні обробника.
  # Замінює AR-валідації моделі, які ігноруються при insert_all (Series D).
  # CSQ діапазон: 0-31 (нормальний сигнал) або 99 (невизначений/відсутній) — стандарт 3GPP 27.007.
  def valid_gateway_stats?(stats)
    voltage_mv          = stats[:voltage_mv]
    temperature_c       = stats[:temperature_c]
    cellular_signal_csq = stats[:cellular_signal_csq]

    return false if voltage_mv.nil? || temperature_c.nil? || cellular_signal_csq.nil?

    VALID_CSQ_VALUES.cover?(cellular_signal_csq.to_i) || cellular_signal_csq.to_i == 99
  end
end
