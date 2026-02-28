# frozen_string_literal: true

class AlertDispatchService
  # Фізичні пороги (Hardware Truths)
  FIRE_TEMP_THRESHOLD_C = 60
  SEISMIC_ACOUSTIC_THRESHOLD = 200
  PEST_ACOUSTIC_THRESHOLD = 50

  def self.analyze_and_trigger!(telemetry_log)
    tree = telemetry_log.tree
    cluster = tree.cluster
    family = tree.tree_family

    # 1. ВАНДАЛІЗМ (Zero-Trust Breach)
    if telemetry_log.bio_status_tamper_detected? || telemetry_log.voltage_mv < 100
      create_and_dispatch_alert!(
        cluster: cluster, tree: tree, severity: :critical,
        alert_type: :vandalism_breach,
        message: "🚨 КРИТИЧНО: Втручання або втрата живлення! DID: #{tree.did}"
      )
      return # Припиняємо аналіз, залізо скомпрометовано
    end

    # 2. ПОЖЕЖА або ПИЛКА (Thermal and Acoustic Chaos)
    if telemetry_log.temperature_c >= FIRE_TEMP_THRESHOLD_C || telemetry_log.bio_status_anomaly?
      create_and_dispatch_alert!(
        cluster: cluster, tree: tree, severity: :critical,
        alert_type: :fire_detected,
        message: "🔥 КАТАСТРОФА: Термістор #{telemetry_log.temperature_c}°C. Ризик пожежі або вирубки! Сектор: #{cluster.name}"
      )
      return
    end

    # 3. ЗЕМЛЕТРУС (Seismic Pulse)
    if telemetry_log.acoustic_events >= SEISMIC_ACOUSTIC_THRESHOLD
      create_and_dispatch_alert!(
        cluster: cluster, tree: tree, severity: :critical,
        alert_type: :seismic_anomaly,
        message: "🌋 СЕЙСМІКА: Аномальний резонанс (#{telemetry_log.acoustic_events}). DID: #{tree.did}"
      )
    end

    # 4. ПОСУХА ТА АТРАКТОР (Mathematical Homeostasis)
    is_out_of_homeostasis = !SilkenNet::Attractor.homeostatic?(telemetry_log.z_value, family)

    if telemetry_log.bio_status_stress? || is_out_of_homeostasis
      msg = if is_out_of_homeostasis && !telemetry_log.bio_status_stress?
              "🌀 АТРАКТОР: Вихід за межі орбіти (Z: #{telemetry_log.z_value}). Передвісник стресу."
      else
              "💧 ПОСУХА: Гідрологічний стрес зафіксовано."
      end

      create_and_dispatch_alert!(
        cluster: cluster, tree: tree, severity: :medium,
        alert_type: :severe_drought, message: msg
      )
    end

    # 5. ШКІДНИКИ (The Silent Eaters)
    if telemetry_log.acoustic_events > PEST_ACOUSTIC_THRESHOLD &&
       telemetry_log.acoustic_events < SEISMIC_ACOUSTIC_THRESHOLD &&
       telemetry_log.bio_status_stress?

      create_and_dispatch_alert!(
        cluster: cluster, tree: tree, severity: :medium,
        alert_type: :insect_epidemic,
        message: "🪲 БІО-ЗАГРОЗА: Виявлено акустичний сигнатур короїда. DID: #{tree.did}"
      )
    end
  end

  private_class_method def self.create_and_dispatch_alert!(cluster:, tree:, severity:, alert_type:, message:)
    # Захист від шторму повідомлень
    return if EwsAlert.where(tree: tree, alert_type: alert_type)
                     .where("created_at > ?", 5.minutes.ago)
                     .exists?

    alert = EwsAlert.create!(
      cluster: cluster, tree: tree, severity: severity,
      alert_type: alert_type, message: message
    )

    Rails.logger.warn "🚨 [EWS ALERT] #{alert_type} | #{tree.did}"

    # Миттєва реакція актуаторів (Клапани поливу / Сирени)
    EmergencyResponseService.call(alert) if defined?(EmergencyResponseService)

    # Сповіщення патрульних (SMS / Push / Telegram)
    AlertNotificationWorker.perform_async(alert.id)
  end
end
