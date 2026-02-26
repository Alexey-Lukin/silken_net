# frozen_string_literal: true

class EmergencyResponseService
  def self.call(ews_alert)
    cluster = ews_alert.cluster

    # Знаходимо всі робочі механізми в цьому лісі
    available_actuators = Actuator.joins(:gateway)
                                  .where(gateways: { cluster_id: cluster.id })
                                  .where(state: :idle)

    case ews_alert.alert_type.to_sym

    # СЦЕНАРІЙ: КРИТИЧНА ПОСУХА (Атрактор Лоренца падає)
    when :severe_drought
      valves = available_actuators.device_type_water_valve
      valves.each do |valve|
        Rails.logger.info "💧 [Mitigation] Вмикаємо полив! Клапан: #{valve.id}"
        # Відправляємо команду на відкриття клапана на 2 години (7200 секунд)
        ActuatorCommandWorker.perform_async(valve.id, "OPEN_VALVE", 7200)
      end

    # СЦЕНАРІЙ: ПОЖЕЖА (Термістори > 60°C)
    when :biological_threat # Або окремий тип :fire_detected
      valves = available_actuators.device_type_water_valve
      sirens = available_actuators.device_type_fire_siren

      # Відкриваємо воду на максимум і вмикаємо сирени для відлякування браконьєрів/попередження людей
      valves.each { |v| ActuatorCommandWorker.perform_async(v.id, "OPEN_VALVE", 14400) }
      sirens.each { |s| ActuatorCommandWorker.perform_async(s.id, "ACTIVATE_SIREN", 3600) }

    # СЦЕНАРІЙ: ЗЕМЛЕТРУС (Сейсмічний метаматеріал зловив резонанс > 1500 mV)
    when :seismic_anomaly
      beacons = available_actuators.device_type_seismic_beacon
      beacons.each do |beacon|
        Rails.logger.warn "🌋 [Mitigation] Сейсмічна тривога! Вмикаємо маяки."
        ActuatorCommandWorker.perform_async(beacon.id, "ACTIVATE_BEACON", 3600)
      end
    end
  end
end
