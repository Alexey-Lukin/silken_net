# frozen_string_literal: true

class EmergencyResponseService
  def self.call(ews_alert)
    cluster = ews_alert.cluster

    # Знаходимо всі робочі механізми в цьому лісі
    # Ми шукаємо і idle, і ті, що вже працюють (active), щоб потенційно продовжити дію
    available_actuators = Actuator.joins(:gateway)
                                  .where(gateways: { cluster_id: cluster.id })
                                  .where(state: [:idle, :active])

    if available_actuators.empty?
      Rails.logger.warn "⚠️ [Emergency] Кластер #{cluster.id}: Актуатори недоступні."
      return
    end

    case ews_alert.alert_type.to_sym
    # СИНХРОНІЗАЦІЯ: Використовуємо символи з AlertDispatchService
    when :severe_drought
      valves = available_actuators.water_valve
      dispatch_commands(valves, "OPEN_VALVE", 7200, ews_alert)

    when :insect_epidemic, :fire_detected
      valves = available_actuators.water_valve
      sirens = available_actuators.fire_siren
      
      dispatch_commands(valves, "OPEN_VALVE", 14400, ews_alert)
      dispatch_commands(sirens, "ACTIVATE_SIREN", 3600, ews_alert)

    when :seismic_anomaly
      beacons = available_actuators.seismic_beacon
      dispatch_commands(beacons, "ACTIVATE_BEACON", 3600, ews_alert)
      
    else
      Rails.logger.info "ℹ️ [Emergency] Тип тривоги #{ews_alert.alert_type} не вимагає активації актуаторів."
    end
  end

  private_class_method def self.dispatch_commands(actuators, command_code, duration, alert)
    actuators.each do |actuator|
      # 1. Створюємо запис команди для історії та аудиту
      # Це дозволить інвестору бачити: "Система врятувала дерево №42 о 14:00"
      ActuatorCommand.create!(
        actuator: actuator,
        ews_alert: alert,
        command_payload: command_code,
        duration_seconds: duration,
        status: :issued
      )

      # 2. Змінюємо стан на :pending (черга на відправку через CoAP)
      actuator.update!(state: :pending)
      
      # 3. Асинхронний запуск фізичного процесу
      ActuatorCommandWorker.perform_async(actuator.id, command_code, duration)
    end
  end
end
