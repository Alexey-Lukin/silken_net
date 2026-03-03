# frozen_string_literal: true

class EmergencyResponseService
  def self.call(ews_alert)
    cluster = ews_alert.cluster

    # Знаходимо всі працездатні актуатори в секторі (Кластері)
    # [СИНХРОНІЗОВАНО]: Враховуємо тільки ті шлюзи, що онлайн
    available_actuators = Actuator.joins(:gateway)
                                  .where(gateways: { cluster_id: cluster.id })
                                  .where(gateways: { last_seen_at: 1.hour.ago..Time.current })
                                  .where(state: [ :idle, :active ])

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

  MAX_COMMAND_DURATION = 3600

  private_class_method def self.dispatch_commands(actuators, command_code, duration, alert)
    return if actuators.empty?

    # [FIX-3]: Пріоритезація — спершу активуємо актуатори ближчих шлюзів
    ordered_actuators = prioritize_by_proximity(actuators, alert)

    # [FIX-1]: Розбиваємо тривалість на серії по MAX_COMMAND_DURATION,
    # щоб не порушити валідацію ActuatorCommand (≤3600с)
    chunks = duration_chunks(duration)

    # [FIX-2]: Масове створення команд одним INSERT замість N окремих
    now = Time.current
    attrs = ordered_actuators.map do |actuator|
      chunks.map do |chunk_duration|
        {
          actuator_id: actuator.id,
          ews_alert_id: alert.id,
          command_payload: command_code,
          duration_seconds: chunk_duration,
          status: ActuatorCommand.statuses[:issued],
          created_at: now,
          updated_at: now
        }
      end
    end.flatten

    begin
      result = ActuatorCommand.insert_all(attrs, returning: %w[id])
      result.each { |row| ActuatorCommandWorker.perform_async(row["id"]) }
    rescue => e
      Rails.logger.error "🛑 [Emergency Error] Масове створення наказів провалене: #{e.message}"
    end
  end

  # Розбиваємо загальну тривалість на частини по MAX_COMMAND_DURATION
  private_class_method def self.duration_chunks(total_duration)
    return [ total_duration ] if total_duration <= MAX_COMMAND_DURATION

    full_chunks = total_duration / MAX_COMMAND_DURATION
    remainder = total_duration % MAX_COMMAND_DURATION

    chunks = Array.new(full_chunks, MAX_COMMAND_DURATION)
    chunks << remainder if remainder > 0
    chunks
  end

  # Сортуємо актуатори за відстанню їхнього шлюзу до дерева-джерела тривоги
  private_class_method def self.prioritize_by_proximity(actuators, alert)
    tree = alert.tree
    return actuators unless tree&.latitude.present? && tree&.longitude.present?

    actuators.order(
      Arel.sql(
        ActiveRecord::Base.sanitize_sql_array([
          "POWER(gateways.latitude - ?, 2) + POWER(gateways.longitude - ?, 2) ASC NULLS LAST",
          tree.latitude, tree.longitude
        ])
      )
    )
  end
end
