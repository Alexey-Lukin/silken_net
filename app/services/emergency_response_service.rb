# frozen_string_literal: true

class EmergencyResponseService
  def self.call(ews_alert)
    cluster = ews_alert.cluster

    # Знаходимо всі працездатні актуатори в секторі (Кластері)
    # [СИНХРОНІЗОВАНО]: Враховуємо тільки ті шлюзи, що онлайн
    available_actuators = Actuator.joins(:gateway)
                                  .where(gateways: { cluster_id: cluster.id })
                                  .where(gateways: { last_seen_at: 1.hour.ago..Time.current })
                                  .where(state: [:idle, :active])

    if available_actuators.empty?
      Rails.logger.warn "⚠️ [Emergency] Кластер #{cluster.name}: Не знайдено доступних інструментів відгуку."
      return
    end

    # Визначаємо протокол дій на основі типу загрози
    case ews_alert.alert_type.to_sym
    when :severe_drought
      # Полив на 2 години
      dispatch_commands(available_actuators.device_type_water_valve, "OPEN_VALVE", 7200, ews_alert)

    when :fire_detected
      # Максимальний полив на 4 години та сирени для евакуації/сповіщення
      dispatch_commands(available_actuators.device_type_water_valve, "OPEN_VALVE", 14400, ews_alert)
      dispatch_commands(available_actuators.device_type_fire_siren, "ACTIVATE_SIREN", 3600, ews_alert)

    when :insect_epidemic
      # Локальна обробка або полив для підтримки імунітету дерева
      dispatch_commands(available_actuators.device_type_water_valve, "OPEN_VALVE", 3600, ews_alert)

    when :seismic_anomaly
      # Активація маяків для візуального позначення зони небезпеки
      dispatch_commands(available_actuators.device_type_seismic_beacon, "ACTIVATE_BEACON", 1800, ews_alert)
      
    else
      Rails.logger.info "ℹ️ [Emergency] Тип тривоги #{ews_alert.alert_type} обробляється лише сповіщенням людей."
    end
  end

  private_class_method def self.dispatch_commands(actuators, command_code, duration, alert)
    return if actuators.empty?

    actuators.each do |actuator|
      # [ДЗЕРКАЛЬНА СИНХРОНІЗАЦІЯ]:
      # Створення цього запису є тригером для ActuatorCommandWorker.
      # Ми обгортаємо це в begin/rescue, щоб збій одного наказу не зупинив порятунок всього лісу.
      begin
        ActuatorCommand.create!(
          actuator: actuator,
          ews_alert: alert,
          command_payload: command_code,
          duration_seconds: duration,
          status: :issued
        )
      rescue => e
        Rails.logger.error "🛑 [Emergency Error] Не вдалося віддати наказ для #{actuator.name}: #{e.message}"
      end
    end
  end
end
