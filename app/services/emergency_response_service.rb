# frozen_string_literal: true

class EmergencyResponseService
  def self.call(ews_alert)
    cluster = ews_alert.cluster

    # Знаходимо всі робочі механізми в цьому лісі, які готові прийняти команду
    available_actuators = Actuator.joins(:gateway)
                                  .where(gateways: { cluster_id: cluster.id })
                                  .where(state: :idle)

    if available_actuators.empty?
      Rails.logger.warn "⚠️ [Emergency] Немає доступних актуаторів (idle) для кластера #{cluster.id}! Фізичне пом'якшення неможливе."
      return
    end

    case ews_alert.alert_type.to_sym

    # СЦЕНАРІЙ: КРИТИЧНА ПОСУХА (Атрактор Лоренца падає)
    when :severe_drought
      valves = available_actuators.where(device_type: :water_valve)
      dispatch_commands(valves, "OPEN_VALVE", 7200)

    # СЦЕНАРІЙ: ПОЖЕЖА АБО БРАКОНЬЄРИ (Термістори > 60°C або TinyML зловив бензопилу)
    when :biological_threat, :fire_detected
      valves = available_actuators.where(device_type: :water_valve)
      sirens = available_actuators.where(device_type: :fire_siren)

      # Відкриваємо воду на максимум і вмикаємо сирени для відлякування
      dispatch_commands(valves, "OPEN_VALVE", 14400)
      dispatch_commands(sirens, "ACTIVATE_SIREN", 3600)

    # СЦЕНАРІЙ: ЗЕМЛЕТРУС (Сейсмічний метаматеріал зловив резонанс > 1500 mV)
    when :seismic_anomaly
      beacons = available_actuators.where(device_type: :seismic_beacon)
      dispatch_commands(beacons, "ACTIVATE_BEACON", 3600)
      
    else
      Rails.logger.info "ℹ️ [Emergency] Тип тривоги #{ews_alert.alert_type} не потребує фізичного втручання актуаторів."
    end
  end

  # =========================================================================
  # ІНКАПСУЛЬОВАНА ЛОГІКА ДИСПЕТЧЕРИЗАЦІЇ
  # =========================================================================
  private_class_method def self.dispatch_commands(actuators, command, duration_seconds)
    actuators.each do |actuator|
      Rails.logger.info "⚡ [Mitigation] Відправка команди #{command} (#{duration_seconds}s) на актуатор #{actuator.id}"
      
      # Миттєво змінюємо стан на :pending, щоб наступний алерт не створив дублікат команди.
      # Справжній стан :active або :idle повернеться через зворотну телеметрію від Королеви.
      actuator.update!(state: :pending)
      
      # Делегуємо виконання асинхронному воркеру (який звернеться до CoAP Client)
      ActuatorCommandWorker.perform_async(actuator.id, command, duration_seconds)
    end
  end
end
