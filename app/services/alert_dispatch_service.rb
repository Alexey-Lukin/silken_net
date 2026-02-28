# frozen_string_literal: true

class AlertDispatchService
  # Фізичні пороги
  FIRE_TEMP_THRESHOLD_C = 60
  SEISMIC_ACOUSTIC_THRESHOLD = 200 
  PEST_ACOUSTIC_THRESHOLD = 50

  def self.analyze_and_trigger!(telemetry_log)
    tree = telemetry_log.tree
    cluster = tree.cluster
    family = tree.tree_family

    # 1. ВАНДАЛІЗМ (Найвищий пріоритет)
    # [ВИПРАВЛЕНО]: Використовуємо правильний префікс енума (bio_status_)
    if telemetry_log.bio_status_tamper_detected? || telemetry_log.voltage_mv < 100
      create_and_dispatch_alert!(
        cluster: cluster, tree: tree, severity: :critical, 
        alert_type: :vandalism_breach,
        message: "КРИТИЧНО: Зафіксовано втручання або втрату живлення! DID: #{tree.did}"
      )
      return 
    end

    # 2. ПОЖЕЖА або РОБОТА ПИЛКОЮ
    if telemetry_log.temperature_c >= FIRE_TEMP_THRESHOLD_C || telemetry_log.bio_status_anomaly?
      create_and_dispatch_alert!(
        cluster: cluster, tree: tree, severity: :critical, 
        alert_type: :fire_detected,
        message: "КАТАСТРОФА: Термістор фіксує #{telemetry_log.temperature_c}°C або аномалію ксилеми. Ризик пожежі/вирубки!"
      )
      return # При пожежі інші алерти не мають сенсу
    end

    # 3. ЗЕМЛЕТРУС (Сейсмічний резонанс)
    if telemetry_log.acoustic_events >= SEISMIC_ACOUSTIC_THRESHOLD
      create_and_dispatch_alert!(
        cluster: cluster, tree: tree, severity: :critical, 
        alert_type: :seismic_anomaly,
        message: "СЕЙСМІКА: Аномальний резонанс (#{telemetry_log.acoustic_events}/255). Можливий тектонічний зсув."
      )
    end

    # 4. ПОСУХА ТА АТРАКТОР ЛОРЕНЦА
    # Математична перевірка гомеостазу через Z-value
    is_out_of_homeostasis = !SilkenNet::Attractor.homeostatic?(telemetry_log.z_value, family)
    
    if telemetry_log.bio_status_stress? || is_out_of_homeostasis
      msg = if is_out_of_homeostasis && !telemetry_log.bio_status_stress?
              "ПОПЕРЕДЖЕННЯ: Атрактор вийшов за межі (Z:#{telemetry_log.z_value}). Рання ознака стресу."
            else
              "ПОСУХА: Дерево у стані гідрологічного стресу."
            end

      # [ВИПРАВЛЕНО]: Замінено неіснуючий :high на :medium
      create_and_dispatch_alert!(
        cluster: cluster, tree: tree, severity: :medium, 
        alert_type: :severe_drought, message: msg
      )
    end

    # 5. ШКІДНИКИ (Короїд)
    if telemetry_log.acoustic_events > PEST_ACOUSTIC_THRESHOLD && 
       telemetry_log.acoustic_events < SEISMIC_ACOUSTIC_THRESHOLD && 
       telemetry_log.bio_status_stress?
       
      # [ВИПРАВЛЕНО]: Замінено неіснуючий :high на :medium
      create_and_dispatch_alert!(
        cluster: cluster, tree: tree, severity: :medium, 
        alert_type: :insect_epidemic,
        message: "БІО-ЗАГРОЗА: Акустична емісія характерна для личинок короїда."
      )
    end
  end

  private_class_method def self.create_and_dispatch_alert!(cluster:, tree:, severity:, alert_type:, message:)
    # Захист від спаму: не створюємо дублікат, якщо такий самий алерт був створений менше 5 хвилин тому
    recent_alert = EwsAlert.where(tree: tree, alert_type: alert_type)
                           .where("created_at > ?", 5.minutes.ago)
                           .exists?
    return if recent_alert

    alert = EwsAlert.create!(
      cluster: cluster, tree: tree, severity: severity, 
      alert_type: alert_type, message: message
    )

    Rails.logger.warn "🚨 [ALERT] #{alert_type} для #{tree.did}"

    # Передаємо керування актуаторам (Клапани / Сирени)
    EmergencyResponseService.call(alert) if defined?(EmergencyResponseService)
    
    # Сповіщаємо людей (SMS / Push)
    notify_stakeholders(alert)
  end

  private_class_method def self.notify_stakeholders(alert)
    AlertNotificationWorker.perform_async(alert.id)
  end
end
